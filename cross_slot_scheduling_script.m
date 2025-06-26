function energy_gain = cross_slot_scheduling_script(k0, scs, packet_frequency, T_total)
    % Parametry symulacji
    % k0: opóźnienie w slotach (np. 1 dla cross-slot, 0 dla same-slot)
    % scs: subcarrier spacing [kHz] (15, 30, 60, 120)
    % packet_frequency: częstotliwość pakietów [ms]
    % T_total: całkowity czas symulacji [ms]
    
    % Oblicz długość slotu w ms w zależności od SCS
    slot_duration = 1 / (scs / 15); % Dla 15 kHz: 1 ms, dla 30 kHz: 0.5 ms, itd.
    ofdm_symbol_length = 71.36 / (scs * 1000 / 15);

    fprintf(" OFDM symbol length %.5f\n", ofdm_symbol_length);
    fprintf(" Slot duration %.2f\n", slot_duration);

    % Liczba slotów w symulacji
    num_slots = T_total / slot_duration;
    co_ile_slotow_pakiet = packet_frequency/slot_duration;
    fprintf(" Number of slots %.2f\n", num_slots);
    fprintf(" Packet_frequency per how many slot %.2f\n", co_ile_slotow_pakiet);

    % Symulacja
    total_energy_cross_slot = 0;
    total_energy_same_slot = 0;

    sleep_time = 11 * ofdm_symbol_length;
    energy_used_during_sleep = 0;

    if (sleep_time) >= 12.035  % Deep Sleep
        fprintf("DEEP SLEEP\n");
        transition_power = 450;
        sleep_power = 1;
        energy_used_during_sleep = transition_power * 0.533 + sleep_power * (sleep_time - 0.533);

    elseif (sleep_time) >= 0.425  % Light Sleep
        fprintf("LIGHT SLEEP\n");
        transition_power = 100;
        sleep_power = 20;
        energy_used_during_sleep = transition_power * 0.133 + sleep_power * (sleep_time - 0.133);

    else  % Micro Sleep
        fprintf("MICRO SLEEP\n");
        energy_used_during_sleep = 45 * sleep_time;
    end

    fprintf("rest time  %.2f\n", num_slots);
    
    for slot = 1:num_slots
        % pakiet dla cross-slot - normalnie dla same slot
        if mod(slot, co_ile_slotow_pakiet) == k0  && slot/co_ile_slotow_pakiet > 1
            total_energy_cross_slot = total_energy_cross_slot + (14 * ofdm_symbol_length * 300);
            total_energy_same_slot = total_energy_same_slot + (14 * ofdm_symbol_length * 100);
            fprintf("Slot nr %d, w tym slocie dla k0 jest PDSCH\n Zużycie energii cross slot scheduling = %.2f, zużycie energi same slot scheduling %.2f\n", slot, total_energy_cross_slot, total_energy_same_slot);
        
        % pakiet dla same slot - sleep dla cross slot
        elseif mod(slot, co_ile_slotow_pakiet) == 0
            total_energy_cross_slot = total_energy_cross_slot + (3 * ofdm_symbol_length * 100) + energy_used_during_sleep;
            total_energy_same_slot = total_energy_same_slot + (14 * ofdm_symbol_length * 300);
            fprintf("Slot nr %d, w tym slocie dla same slot jest PDSCH\n Zużycie energii cross slot scheduling = %.2f, zużycie energi same slot scheduling %.2f\n", slot, total_energy_cross_slot, total_energy_same_slot);
        
        % nie ma pakietu - normalnie dla same slot i sleep dla cross slot   
        else
            total_energy_cross_slot = total_energy_cross_slot + (3 * ofdm_symbol_length * 100) + energy_used_during_sleep;
            total_energy_same_slot = total_energy_same_slot + (14 * ofdm_symbol_length * 100);
            fprintf("Slot nr %d bez PDSCH\nZużycie energii cross slot scheduling = %.2f, zużycie energi same slot scheduling %.2f\n", slot, total_energy_cross_slot, total_energy_same_slot);

        end

    end
    
    % Oblicz energy gain (zysk energetyczny w %)
    energy_gain = (total_energy_cross_slot / total_energy_same_slot) * 100;

    if k0 == 0 
        energy_gain = 100;
    end
    
    % Wyświetl wyniki
    fprintf('---- Wyniki dla SCS = %d kHz, k0 = %d ----\n', scs, k0);
    fprintf('Zużycie energii (cross-slot): %.2f units\n', total_energy_cross_slot);
    fprintf('Zużycie energii (same-slot):  %.2f units\n', total_energy_same_slot);
    fprintf('Energy gain: %.2f%%\n', energy_gain);
end