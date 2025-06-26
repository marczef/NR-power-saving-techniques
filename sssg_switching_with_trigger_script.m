function [energy_gain, delays] = sssg_switching_with_trigger_script(T_total, scs, SSSG0_frequency, SSSG1_frequency, P_switch, ...
    packet_frequency, packet_data_duration, buffor_before_dci)
    % Input parameters
    fprintf('\n=== Starting DRX Simulation ===\n');
    fprintf('Total simulation time: %d ms\n', T_total);
    fprintf('SSSG0 frequency in slots: %d \n', SSSG0_frequency);
    fprintf('SSSG1 frequency in slots: %d \n', SSSG1_frequency);
    fprintf('P switch value in slots: %d ms\n', P_switch);
    fprintf('Packet frequency: %d ms\n', packet_frequency);
    fprintf('Buffor in ms indicating when DCI 2_0 is send: %d \n', buffor_before_dci);
    fprintf('Packet reception time: %d ms\n\n', packet_data_duration);

    % Initialize variables
    slot_duration = 1 / (scs / 15); % Dla 15 kHz: 1 ms, dla 30 kHz: 0.5 ms, itd.

    %SSSG0 energy usage
    sssg0_no_data_energy = slot_duration * 100;
    sssg0_data_energy = slot_duration * 300;

    %%% available sleep energy in SSSG1
    if (SSSG1_frequency - 1) * slot_duration >= 12.035  % Deep Sleep
        fprintf("DEEP SLEEP\n");
        transition_power = 450;
        sleep_power = 1;
        available_sleep_energy = transition_power * 0.533 + sleep_power * (((SSSG1_frequency - 1) * slot_duration) - 0.533);
    elseif (SSSG1_frequency - 1) * slot_duration >= 0.425  % Light Sleep
        fprintf("LIGHT SLEEP\n");
        transition_power = 100;
        sleep_power = 20;
        available_sleep_energy = transition_power * 0.133 + sleep_power * (((SSSG1_frequency - 1) * slot_duration) - 0.133);

    else  % Micro Sleep
        fprintf("MICRO SLEEP\n");
        available_sleep_energy = 45 * ((SSSG1_frequency - 1) * slot_duration);
    end
    
    % SSSG1 energy usage
    sssg1_no_data_energy = available_sleep_energy + slot_duration * 100;
    sssg1_data_energy = available_sleep_energy + slot_duration * 300;
    fprintf('SSSG1 no data: %.2f\n', sssg1_no_data_energy);

    buffor_SSSG0 = ceil(buffor_before_dci * slot_duration);
    buffor_SSSG1 = ceil(buffor_before_dci / slot_duration / SSSG1_frequency);

    switching_type = SSSG0_frequency;
    remaining_time = T_total;
    monitoring_counter = buffor_SSSG0;
    monitoring_type = 'buffor_before_dci';
    total_energy_switching = 0;
    total_energy_no_switching = 0;

    packet_arrivals = packet_frequency:packet_frequency:T_total;
    next_packet_index = 1;
    pending_packets = []; % Array to store packets that arrived during sleep
    processing_packet = false;
    packet_processing_counter = 0;
    delays_array = [];

    % lecimy po jednym slocie - jedna iteracja jeden czas search space
    % groupy
    while remaining_time > 0

        current_slot_time = (T_total - remaining_time);

        while next_packet_index <= length(packet_arrivals)
            current_packet_time = packet_arrivals(next_packet_index);
            if current_packet_time <= current_slot_time
                start_value = packet_arrivals(next_packet_index);
                values_to_add = start_value + (0:slot_duration:slot_duration*packet_data_duration-slot_duration);
                pending_packets = [pending_packets, values_to_add];
                next_packet_index = next_packet_index + 1;
            else
                break;
            end
        end

        if switching_type == SSSG0_frequency 
            fprintf('Time %.2f ms | SSSG0 monitoring | ', current_slot_time);
                
            % Check if we should start processing a packet
            if ~isempty(pending_packets) && ~processing_packet
                processing_packet = true;
                packet_processing_counter = packet_data_duration;
                fprintf('Packet detected, starting processing for %.2f slots | ', packet_data_duration);
            end

            if processing_packet
                % Processing packet - use data energy
                total_energy_switching = total_energy_switching + sssg0_data_energy;
                total_energy_no_switching = total_energy_no_switching + sssg0_data_energy;

                time_until_packet = pending_packets(1) - current_slot_time;
                fprintf('time_until_packet %.2f ms \n', time_until_packet);
                delays_array = [delays_array, abs(time_until_packet)];
                pending_packets(1) = []; % Remove the packet we're processing
                fprintf('pending_packets %.2f ms \n', pending_packets);                
                packet_processing_counter = packet_processing_counter - 1;
                fprintf("   zostało packet_processing_counter %d \n", packet_processing_counter);

                if packet_processing_counter <= 0
                    monitoring_counter = buffor_SSSG0;
                    monitoring_type = 'buffor_before_dci';
                    processing_packet = false;
                    fprintf('Packet processing complete | ');
                end
                
                remaining_time = remaining_time - slot_duration * SSSG0_frequency;
                fprintf('Energy used: %.2f mJ (switching) / %.2f mJ (no switch)\n', ...
                    total_energy_switching, total_energy_no_switching);
            
            else
                % Normal monitoring
                if monitoring_counter > 0
                    total_energy_switching = total_energy_switching + sssg0_no_data_energy;
                    total_energy_no_switching = total_energy_no_switching + sssg0_no_data_energy;
                    monitoring_counter = monitoring_counter - 1;
                    remaining_time = remaining_time - slot_duration * SSSG0_frequency;
                    
                    fprintf('Counter: %d | Energy used: %.2f mJ (switching) / %.2f mJ (no switch)\n', ...
                        monitoring_counter, total_energy_switching, total_energy_no_switching);
                
                else
                    % State transition
                    switch monitoring_type 
                        case 'buffor_before_dci'
                            monitoring_counter = P_switch;
                            monitoring_type = 'p_switch';
                            fprintf('Switching to p_switch monitoring (counter: %d)\n', monitoring_counter);
                        case 'p_switch'
                            switching_type = SSSG1_frequency;
                            monitoring_counter = Inf;
                            monitoring_type = 'SSSG1_waiting_for_trigger';
                            fprintf('Switching to SSSG1 monitoring (every %d slots)\n', SSSG1_frequency);
                    end
                end
            end

        elseif switching_type == SSSG1_frequency
            fprintf('Time %.2f ms | SSSG1 monitoring | ', current_slot_time);
            
            % Check if we should start processing a packet
            if ~isempty(pending_packets) && ~processing_packet
                processing_packet = true;
                packet_processing_counter = packet_data_duration;
                fprintf('Packet detected, starting processing for %.2f slots | ', packet_data_duration);
            end
            
            if processing_packet
                % Processing packet during p_switch - use data energy
                total_energy_switching = total_energy_switching + sssg1_data_energy;
                total_energy_no_switching = total_energy_no_switching + sssg0_data_energy + sssg0_no_data_energy * (SSSG1_frequency - 1);

                time_until_packet = pending_packets(1) - current_slot_time;
                fprintf('time_until_packet %.2f ms \n', time_until_packet);
                delays_array = [delays_array, abs(time_until_packet)];
                pending_packets(1) = [];
                fprintf('pending_packets %.2f ms \n', pending_packets);    
                monitoring_counter = monitoring_counter - SSSG1_frequency;
                packet_processing_counter = packet_processing_counter - 1;
                fprintf("   zostało packet_processing_counter %d \n", packet_processing_counter);


                if packet_processing_counter <= 0
                    processing_packet = false;
                    fprintf('Packet processing complete | ');
                end

                switch monitoring_type 
                    case 'SSSG1_waiting_for_trigger'
                        monitoring_counter = buffor_SSSG1;
                        monitoring_type = 'buffor_before_dci';
                        fprintf('Switching to buffor_before_dci monitoring (counter: %d)\n', monitoring_counter);
                    case 'p_switch'
                        if monitoring_counter <= 0
                            switching_type = SSSG0_frequency;
                            monitoring_counter = buffor_SSSG0;
                            monitoring_type = 'buffor_before_dci';
                            fprintf('Switching to SSSG0 monitoring (every %d slots)\n', SSSG0_frequency);
                        end
                    case 'buffor_before_dci'
                        if monitoring_counter <= 0
                            monitoring_counter = P_switch;
                            monitoring_type = 'p_switch';
                            fprintf('Switching to p_switch monitoring (counter: %d)\n', monitoring_counter);
                        end
                end
                
                remaining_time = remaining_time - slot_duration * SSSG1_frequency;
                fprintf('Counter: %d | Energy used: %.2f mJ (switching) / %.2f mJ (no switch)\n', ...
                        monitoring_counter, total_energy_switching, total_energy_no_switching);
            
            else
                % Normal monitoring
                if monitoring_counter > 0
                    total_energy_switching = total_energy_switching + sssg1_no_data_energy;
                    total_energy_no_switching = total_energy_no_switching + sssg0_no_data_energy * SSSG1_frequency;
                    monitoring_counter = monitoring_counter - SSSG1_frequency;
                    remaining_time = remaining_time - slot_duration * SSSG1_frequency;
                    
                    fprintf('Counter: %d | Energy used: %.2f mJ (switching) / %.2f mJ (no switch)\n', ...
                        monitoring_counter, total_energy_switching, total_energy_no_switching);
                
                else
                    % State transition
                    switch monitoring_type 
                        case 'buffor_before_dci'
                            monitoring_counter = P_switch;
                            monitoring_type = 'p_switch';
                            fprintf('Switching to p_switch monitoring (counter: %d)\n', monitoring_counter);
                        case 'p_switch'
                            switching_type = SSSG0_frequency;
                            monitoring_counter = buffor_before_dci;
                            monitoring_type = 'buffor_before_dci';
                            fprintf('Switching to SSSG0 monitoring (every %d slots)\n', SSSG0_frequency);
                    end
                end
            end
        end
    end

    fprintf('\n=== Simulation Results ===\n');
    fprintf('Total energy with switching: %.2f mJ\n', total_energy_switching);
    fprintf('Total energy without switching: %.2f mJ\n', total_energy_no_switching);

    energy_gain = total_energy_switching / total_energy_no_switching * 100;
    delays = mean(delays_array);
    fprintf('Energy gain: %.2f%%\n', energy_gain);
    fprintf('Delays: %.2f%%\n', delays_array);
    fprintf('Mean delay during the simulation: %.1f ms\n', delays_array);
    
end