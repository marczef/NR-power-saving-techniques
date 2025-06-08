function [energy_gain, delays] = drx_script(T_total, longDRX_cycle, inactivity_timer, ...
    on_duration, frequency_of_incoming_packet, packet_reception_time)
    % Input parameters
    fprintf('\n=== Starting DRX Simulation ===\n');
    fprintf('Total simulation time: %d ms\n', T_total);
    fprintf('Long DRX cycle: %d ms\n', longDRX_cycle);
    fprintf('Inactivity timer: %d ms\n', inactivity_timer);
    fprintf('On duration: %d ms\n', on_duration);
    fprintf('Packet frequency: %d ms\n', frequency_of_incoming_packet);
    fprintf('Packet reception time: %d ms\n\n', packet_reception_time);

    % Initialize variables
    remaining_time = T_total;
    E_DRX = 0;
    E_no_sleep = 100 * T_total;
    total_packets_received = 0;
    delays_array = [];
    pending_packets = []; % Array to store packets that arrived during sleep

    current_state = 'inactivity_timer';
    previous_state = '';
    cycle_count = 1;
    on_time_counter = 0;
    
    % Calculate packet arrival times
    packet_arrivals = frequency_of_incoming_packet:frequency_of_incoming_packet:(T_total + frequency_of_incoming_packet);
    next_packet_index = 1;
    
    fprintf('Initial state: %s\n', current_state);
    
    while remaining_time > 0

       current_time = T_total - remaining_time;
        
        % Find all packets that arrived during last sleep period
        if strcmp(previous_state, 'sleep')
            while next_packet_index <= length(packet_arrivals) && ...
                  packet_arrivals(next_packet_index) <= current_time
                pending_packets = [pending_packets, packet_arrivals(next_packet_index)];
                next_packet_index = next_packet_index + 1;
            end
        end

        if ~isempty(pending_packets)
            next_packet_time = pending_packets(1);
            time_until_packet = next_packet_time - current_time;
        else
            if next_packet_index <= length(packet_arrivals)
                next_packet_time = packet_arrivals(next_packet_index);
                time_until_packet = next_packet_time - current_time;
            else
                time_until_packet = Inf;
            end
        end

        % Process current state
        switch current_state
            case 'inactivity_timer'

                if time_until_packet > 0 && time_until_packet <= inactivity_timer

                    % Wait for packet to occur
                    time_to_process = min(time_until_packet, remaining_time);
                    fprintf('INACTIVITY_TIMER: %d ms (Energy: %.1f mJ)\n', time_to_process, 100*time_to_process);
                    E_DRX = E_DRX + 100 * time_to_process;

                    remaining_time = remaining_time - time_to_process;
                    on_time_counter = on_time_counter + time_to_process;
                    fprintf('! STATE ON time counter: %d)\n', on_time_counter);
                    
                    % Go to ON_DURATION STATE
                    fprintf('\n[Packet #%d arrived during INACTIVITY_TIMER at %d ms]\n', next_packet_index, current_time + time_until_packet);
                    fprintf('\n GO TO ON_DURATION IMMEDIATLY \n');
                    delays_array = [delays_array, 0];
    
                    % Update energy stats
                    current_gain = E_DRX / E_no_sleep * 100;
                    fprintf('[Energy after packet] Total: %.1f mJ | Saved: %.1f%%\n', E_DRX, current_gain);
    
                    previous_state = 'inactivity_timer';
                    current_state = 'on_duration';

                    fprintf('-> State change: INACTIVITY_TIMER -> ON_DURATION (Cycle #%d)\n', cycle_count);
                    
                else
                    time_to_process = min(inactivity_timer, remaining_time);
                    E_DRX = E_DRX + 100 * time_to_process;
                    on_time_counter = on_time_counter + time_to_process;
                    
                    fprintf('INACTIVITY_TIMER: %d ms (Energy: %.1f mJ)\n', time_to_process, 100*time_to_process);
                    fprintf('! STATE ON time counter: %d)\n', on_time_counter);

                    remaining_time = remaining_time - time_to_process;
                    
                    previous_state = 'inactivity_timer';
                    current_state = 'sleep';
                    fprintf('-> State change: INACTIVITY_TIMER -> SLEEP (Cycle #%d)\n', cycle_count);
                end
                
            case 'on_duration'
                if time_until_packet < 0
                    % Packet arrived in previous cycle in sleep
                    fprintf('\n[Packet #%d arrived during SLEEP at last cycle at %d ms]\n', next_packet_index, current_time + time_until_packet);
                    
                    num_packets = length(pending_packets);
                    fprintf('\n[Processing %d pending packets that arrived during SLEEP]\n', num_packets);
                    
                    total_processing_time = num_packets * packet_reception_time;
                    
                    if total_processing_time > on_duration
                        time_to_process = min(total_processing_time, remaining_time);
                        packets_processed = min(floor(time_to_process / packet_reception_time), num_packets);
                        actual_processing_time = packets_processed * packet_reception_time;

                        % Update delays for processed packets
                        for i = 1:packets_processed
                            delay = current_time - pending_packets(i);
                            delays_array = [delays_array, delay];
                            fprintf('-> Processing packet arrived at %d ms (delay: %d ms)\n', pending_packets(i), delay);
                        end

                        % Update system state
                        E_DRX = E_DRX + 100 * actual_processing_time;
                        remaining_time = remaining_time - actual_processing_time;
                        total_packets_received = total_packets_received + packets_processed;
                        on_time_counter = on_time_counter + actual_processing_time;
                        fprintf('! STATE ON time counter: %d)\n', on_time_counter);
                        
                        % Remove processed packets
                        pending_packets(1:packets_processed) = [];

                        current_gain = E_DRX / E_no_sleep * 100;
                        fprintf('[Energy after processing %d packets] Total: %.1f mJ | Saved: %.1f%%\n', ...
                            packets_processed, E_DRX, current_gain);
                        
                        previous_state = 'on_duration';
                        current_state = 'inactivity_timer';
                    else
                        % We can process all pending packets in this on_duration
                        time_to_process = min(on_duration, remaining_time);
                        
                        % Update delays for all packets
                        for i = 1:num_packets
                            delay = current_time - pending_packets(i);
                            delays_array = [delays_array, delay];
                            fprintf('-> Processing packet arrived at %d ms (delay: %d ms)\n', ...
                                pending_packets(i), delay);
                        end
                        
                        % Update system state
                        E_DRX = E_DRX + 100 * time_to_process;
                        remaining_time = remaining_time - time_to_process;
                        total_packets_received = total_packets_received + num_packets;
                        on_time_counter = on_time_counter + time_to_process;
                        
                        % Clear pending packets
                        pending_packets = [];
                        
                        % Update energy stats
                        current_gain = E_DRX / E_no_sleep * 100;
                        fprintf('[Energy after processing %d packets] Total: %.1f mJ | Saved: %.1f%%\n', ...
                            num_packets, E_DRX, current_gain);
                        
                        previous_state = 'on_duration';
                        current_state = 'inactivity_timer';
                        fprintf('-> State change: ON_DURATION -> INACTIVITY_TIMER (Cycle #%d)\n', cycle_count);
                    end
             
                elseif time_until_packet >= 0 && time_until_packet <= on_duration
                    fprintf('\n[Packet #%d arrived during ON_DURATION at %d ms]\n', next_packet_index, current_time + time_until_packet);

                    delays_array = [delays_array, 0];
        
                    % Receive packets immediately

                    if time_until_packet + packet_reception_time + inactivity_timer < on_duration
                        time_to_process = min(on_duration, remaining_time);
                        previous_state = 'on_duration';
                        current_state = 'sleep';
                    else
                        time_to_process = min(time_until_packet + packet_reception_time, remaining_time);
                        previous_state = 'on_duration';
                        current_state = 'inactivity_timer';
                    end

                    E_DRX = E_DRX + 100 * time_to_process;
                    fprintf('-> Receiving packets: %d ms (Energy: %.1f mJ)\n', time_to_process, 100*time_to_process);
    
                    remaining_time = remaining_time - time_to_process;
                    total_packets_received = total_packets_received + 1;
                    on_time_counter = on_time_counter + time_to_process;
                    fprintf('! STATE ON time counter: %d\n', on_time_counter);
    
                    % Update energy stats
                    current_gain = E_DRX / E_no_sleep * 100;
                    fprintf('[Energy after packet] Total: %.1f mJ | Saved: %.1f%%\n', E_DRX, current_gain);

                    next_packet_index = next_packet_index + 1;

                    if packet_reception_time + inactivity_timer < on_duration
                        fprintf('-> State change: ON_DURATION -> SLEEP (Cycle #%d)\n', cycle_count);
                    else
                        fprintf('-> State change: ON_DURATION -> INACTIVITY_TIMER (Cycle #%d)\n', cycle_count);
                    end

                else
                    % No packet in previous sleep and during ON_DURATION
                    time_to_process = min(on_duration, remaining_time);

                    E_DRX = E_DRX + 100 * time_to_process;
                    on_time_counter = on_time_counter + time_to_process;
                    fprintf('! STATE ON time counter: %d\n', on_time_counter);
                    fprintf('ON_DURATION: %d ms (Energy: %.1f mJ)\n', time_to_process, 100*time_to_process);
                    
                    remaining_time = remaining_time - time_to_process;
                    
                    previous_state = 'on_duration';
                    current_state = 'sleep';

                    fprintf('-> State change: ON_DURATION -> SLEEP (Cycle #%d)\n', cycle_count);
                end
                
            case 'sleep'
                % Calculate remaining sleep time
                sleep_time_remaining = longDRX_cycle - on_time_counter;

                if sleep_time_remaining <= 0
                    sleep_time_remaining = longDRX_cycle;
                end
                
                on_time_counter = 0;
                time_to_process = min(sleep_time_remaining, remaining_time);
                
                % Determine sleep state
                if (sleep_time_remaining) >= 12.035  % Deep Sleep
                    sleep_type = 'DEEP_SLEEP';
                    transition_power = 450;
                    sleep_power = 1;

                    if (time_to_process ~= sleep_time_remaining)
                        fprintf("NIESKOŃCZONY OSTATNI CYKL DRX \n");
                        if time_to_process <= 0.4
                            fprintf("pierwszy IF \n");
                            energy_used = transition_power * time_to_process;
                        elseif time_to_process > 0.4 && time_to_process <= sleep_time_remaining - 0.133
                            fprintf("drugi IF \n");
                            energy_used = transition_power * 0.4 + sleep_power * (time_to_process - 0.4);
                        elseif time_to_process > sleep_time_remaining - 0.133
                            fprintf("trzeci IF \n");
                            transition_time = 533 - (sleep_time_remaining - time_to_process);
                            energy_used = transition_power * transition_time + sleep_power * (time_to_process - transition_time);
                        end
                    else
                        energy_used = transition_power * 0.533 + sleep_power * (time_to_process - 0.533);
                    end

                elseif (sleep_time_remaining) >= 0.425  % Light Sleep
                    sleep_type = 'LIGHT_SLEEP';
                    transition_power = 100;
                    sleep_power = 20;

                    if (time_to_process ~= sleep_time_remaining)
                        fprintf("NIESKOŃCZONY OSTATNI CYKL DRX \n");
                        if time_to_process <= 0.1
                            fprintf("pierwszy IF \n");
                            energy_used = transition_power * time_to_process;
                        elseif time_to_process > 0.1 && time_to_process <= sleep_time_remaining - 0.033
                            fprintf("drugi IF \n");
                            energy_used = transition_power * 0.1 + sleep_power * (time_to_process - 0.1);
                        elseif time_to_process > sleep_time_remaining - 0.033
                            fprintf("trzeci IF \n");
                            transition_time = 133 - (sleep_time_remaining - time_to_process);
                            energy_used = transition_power * transition_time + sleep_power * (time_to_process - transition_time);
                        end
                    else
                        energy_used = transition_power * 0.133 + sleep_power * (time_to_process - 0.133);
                    end
                else  % Micro Sleep
                    sleep_type = 'MICRO_SLEEP';
                    energy_used = 45 * time_to_process;
                end

                E_DRX = E_DRX + energy_used;
                fprintf('%s: %d ms (Energy: %.1f mJ)\n', sleep_type, time_to_process, energy_used);
                
                remaining_time = remaining_time - time_to_process;

                % Update energy stats periodically
                current_gain = E_DRX / E_no_sleep * 100;
                fprintf('[Energy update] Total: %.1f mJ | Saved: %.1f%%\n', E_DRX, current_gain);
                
                previous_state = 'sleep';
                current_state = 'on_duration';
                fprintf('-> State change: SLEEP -> ON_DURATION\n');

                cycle_count = cycle_count + 1;
               
        end
    end
    
    % Final results
    energy_gain = E_DRX / E_no_sleep * 100;
    delays = mean(delays_array);
    
    fprintf('\n=== Simulation Complete ===\n');
    fprintf('Total packets received: %d\n', total_packets_received);
    fprintf('Total energy consumed: %.1f mJ\n', E_DRX);
    fprintf('Energy without DRX: %.1f mJ\n', E_no_sleep);
    fprintf('Energy used during DRX: %.1f%%\n', energy_gain);
    fprintf('Max delay during the simulation: %.1f ms\n', delays_array);
end
