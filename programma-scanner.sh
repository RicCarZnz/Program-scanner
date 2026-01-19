#!/bin/bash
# ======================================================================
# PROGRAMMA SCANNER - Scansiona TUTTI i metodi di installazione
# ======================================================================

# Funzione per trovare il nome commerciale (se diverso)
get_nome_commerciale() {
    local nome="$1"
    local desktop_file=""
    
    # Cerca nei .desktop per il nome commerciale
    for desktop in /usr/share/applications/*.desktop ~/.local/share/applications/*.desktop; do
        if [ -f "$desktop" ]; then
            # Cerca per nome nell'exec o nel file .desktop
            if grep -qi "$nome" "$desktop" || echo "$desktop" | grep -qi "$nome"; then
                # Estrai il nome commerciale (Name=)
                nome_commerciale=$(grep -i "^Name=" "$desktop" | head -1 | cut -d'=' -f2)
                if [ ! -z "$nome_commerciale" ]; then
                    echo "$nome_commerciale"
                    return 0
                fi
            fi
        fi
    done
    echo "$nome"
}

# Funzione per determinare come è installato
analizza_installazione() {
    local nome="$1"
    local risultati=""
    local trovato=0
    
    # Ottieni nome commerciale
    nome_commerciale=$(get_nome_commerciale "$nome")
    
    risultati="🔍 <b>SCANSIONE PER:</b> $nome_commerciale\n"
    risultati+="========================================\n\n"
    
    # 1. CONTROLLO APT/DPKG (pacchetti Debian)
    echo "1. Scansione APT/dpkg..." >&2
    apt_results=$(dpkg -l | grep -i "$nome" 2>/dev/null)
    if [ ! -z "$apt_results" ]; then
        trovato=1
        package_name=$(echo "$apt_results" | awk '{print $2}' | head -1)
        risultati+="📦 <b>Installato con APT (pacchetto Debian)</b>\n"
        risultati+="   └─ Pacchetto: $package_name\n"
        
        # Info dettagliate
        package_info=$(dpkg -s "$package_name" 2>/dev/null | grep -E "Version|Status|Description")
        while IFS= read -r line; do
            if [[ "$line" == *"Version:"* ]]; then
                risultati+="   └─ Versione: ${line#*: }\n"
            elif [[ "$line" == *"Description:"* ]]; then
                risultati+="   └─ Descrizione: ${line#*: }\n"
            fi
        done <<< "$package_info"
        risultati+="\n"
    fi
    
    # 2. CONTROLLO SNAP
    echo "2. Scansione Snap..." >&2
    snap_results=$(snap list | grep -i "$nome" 2>/dev/null)
    if [ ! -z "$snap_results" ]; then
        trovato=1
        snap_name=$(echo "$snap_results" | awk '{print $1}' | head -1)
        snap_version=$(echo "$snap_results" | awk '{print $2}' | head -1)
        risultati+="🐍 <b>Installato come Snap</b>\n"
        risultati+="   └─ Snap: $snap_name (v$snap_version)\n"
        risultati+="   └─ Confinamento: $(echo "$snap_results" | awk '{print $5}' | head -1)\n\n"
    fi
    
    # 3. CONTROLLO FLATPAK
    echo "3. Scansione Flatpak..." >&2
    flatpak_results=$(flatpak list --app --columns=application,name 2>/dev/null | grep -i "$nome")
    if [ ! -z "$flatpak_results" ]; then
        trovato=1
        flatpak_app=$(echo "$flatpak_results" | head -1 | cut -f1)
        flatpak_name=$(echo "$flatpak_results" | head -1 | cut -f2)
        risultati+="📱 <b>Installato come Flatpak</b>\n"
        risultati+="   └─ Applicazione: $flatpak_name\n"
        risultati+="   └─ ID: $(echo "$flatpak_app" | cut -d'.' -f2-)\n\n"
    fi
    
    # 4. CONTROLLO APPIMAGE
    echo "4. Scansione AppImage..." >&2
    appimage_found=$(find ~ /opt -name "*$nome*.AppImage" 2>/dev/null | head -1)
    if [ ! -z "$appimage_found" ]; then
        trovato=1
        risultati+="📄 <b>Installato come AppImage</b>\n"
        risultati+="   └─ Percorso: $appimage_found\n"
        risultati+="   └─ Tipo: AppImage portabile\n\n"
    fi
    
    # 5. CONTROLLO PIP (Python)
    echo "5. Scansione pip..." >&2
    pip_results=$(pip list 2>/dev/null | grep -i "$nome")
    if [ ! -z "$pip_results" ]; then
        trovato=1
        pip_package=$(echo "$pip_results" | awk '{print $1}' | head -1)
        pip_version=$(echo "$pip_results" | awk '{print $2}' | head -1)
        risultati+="🐍 <b>Installato con pip (Python)</b>\n"
        risultati+="   └─ Pacchetto: $pip_package (v$pip_version)\n\n"
    fi
    
    # 6. CONTROLLO NPM (Node.js)
    echo "6. Scansione npm..." >&2
    npm_results=$(npm list -g 2>/dev/null | grep -i "$nome" | head -5)
    if [ ! -z "$npm_results" ]; then
        trovato=1
        risultati+="📦 <b>Installato con npm (Node.js)</b>\n"
        risultati+="   └─ Pacchetto globale Node.js\n\n"
    fi
    
    # 7. CONTROLLO INSTALLAZIONE MANUALE
    echo "7. Scansione installazioni manuali..." >&2
    manual_paths=$(which "$nome" 2>/dev/null)
    if [ ! -z "$manual_paths" ]; then
        percorso=$(echo "$manual_paths" | head -1)
        if [[ ! "$percorso" =~ ^/(usr|snap|var)/ ]]; then
            trovato=1
            risultati+="🔧 <b>Installazione manuale/script</b>\n"
            risultati+="   └─ Percorso: $percorso\n"
            if [ -f "$HOME/.local/bin/$nome" ]; then
                risultati+="   └─ Tipo: Installazione utente (~/.local/bin)\n\n"
            elif [ -f "/opt/$nome" ]; then
                risultati+="   └─ Tipo: Installazione in /opt\n\n"
            elif [ -f "/usr/local/bin/$nome" ]; then
                risultati+="   └─ Tipo: Installazione in /usr/local\n\n"
            fi
        fi
    fi
    
    # 8. CONTROLLO SCRIPT/BINARI NELLA HOME
    echo "8. Scansione directory personali..." >&2
    home_bin=$(find ~/ -maxdepth 3 -type f -executable -name "*$nome*" 2>/dev/null | head -3)
    if [ ! -z "$home_bin" ]; then
        trovato=1
        risultati+="🏠 <b>Binario nella home directory</b>\n"
        risultati+="   └─ Percorsi trovati:\n"
        while IFS= read -r path; do
            risultati+="      • $path\n"
        done <<< "$home_bin"
        risultati+="\n"
    fi
    
    # 9. CONTROLLO FILE .DESKTOP
    echo "9. Scansione menu applicazioni..." >&2
    desktop_files=$(find /usr/share/applications ~/.local/share/applications -name "*$nome*.desktop" 2>/dev/null)
    if [ ! -z "$desktop_files" ]; then
        trovato=1
        risultati+="🎯 <b>Trovato nel menu applicazioni</b>\n"
        risultati+="   └─ File .desktop:\n"
        while IFS= read -r desktop; do
            app_name=$(grep -i "^Name=" "$desktop" | head -1 | cut -d'=' -f2)
            exec_cmd=$(grep -i "^Exec=" "$desktop" | head -1 | cut -d'=' -f2)
            risultati+="      • $app_name\n"
            risultati+="        ($exec_cmd)\n"
        done <<< "$desktop_files"
        risultati+="\n"
    fi
    
    # Se non trovato
    if [ $trovato -eq 0 ]; then
        risultati+="❌ <b>Programma non trovato</b>\n\n"
        risultati+="<i>Suggerimenti:</i>\n"
        risultati+="• Il nome potrebbe essere diverso\n"
        risultati+="• Prova con il nome esatto\n"
        risultati+="• Il programma potrebbe non essere installato\n"
    else
        # Trovato - aggiungi informazioni generali
        risultati+="\n📊 <b>INFORMAZIONI GENERALI:</b>\n"
        risultati+="----------------------------------------\n"
        
        # Dimensione approssimativa
        if [ ! -z "$package_name" ]; then
            size=$(dpkg-query -s "$package_name" 2>/dev/null | grep "Installed-Size" | cut -d' ' -f2)
            if [ ! -z "$size" ]; then
                size_mb=$(echo "scale=2; $size / 1024" | bc)
                risultati+="📏 Dimensione installata: ${size_mb}MB\n"
            fi
        fi
        
        # Data installazione
        install_date=$(stat -c %y /usr/share/applications/*.desktop 2>/dev/null | grep -i "$nome" | head -1 | cut -d' ' -f1)
        if [ ! -z "$install_date" ]; then
            risultati+="📅 Data installazione: $install_date\n"
        fi
    fi
    
    echo "$risultati"
}

# ======================================================================
# INTERFACCIA GRAFICA
# ======================================================================

# Mostra interfaccia principale
while true; do
    scelta=$(yad --form \
        --title="🔍 SCANNER PROGRAMMI - Kubuntu" \
        --text="<b>Cerca come è installato un programma</b>\n\nInserisci il nome del programma:" \
        --field="Nome programma:" "" \
        --field="Ricerca avanzata:CHK" "FALSE" \
        --button="Cerca!gtk-find:0" \
        --button="Elenco programmi:1" \
        --button="Esci!gtk-quit:2" \
        --width=500 \
        --height=200)
    
    # Controlla uscita
    ret=$?
    
    if [ $ret -eq 2 ]; then
        # Esci
        exit 0
    elif [ $ret -eq 1 ]; then
        # Mostra elenco programmi installati
        programmi=$(paste -d'\n' \
            <(dpkg --get-selections | cut -f1) \
            <(snap list 2>/dev/null | tail -n +2 | cut -d' ' -f1) \
            <(flatpak list --app --columns=application 2>/dev/null | cut -d'.' -f2-) | \
            sort | uniq)
        
        programma_selezionato=$(echo "$programmi" | yad --list \
            --title="Elenco programmi installati" \
            --text="Seleziona un programma:" \
            --column="Programma" \
            --width=600 --height=500 \
            --button="Analizza:0" \
            --button="Indietro:1")
        
        if [ $? -eq 0 ] && [ ! -z "$programma_selezionato" ]; then
            nome_programma=$(echo "$programma_selezionato" | cut -d'|' -f1)
            risultati=$(analizza_installazione "$nome_programma")
            
            # Mostra risultati
            yad --text-info \
                --title="Risultati per: $nome_programma" \
                --text="$risultati" \
                --width=700 --height=500 \
                --button="Nuova ricerca:0" \
                --button="Salva report:1" \
                --button="Esci:2"
            
            # Salva report se richiesto
            if [ $? -eq 1 ]; then
                data_ora=$(date "+%Y-%m-%d_%H-%M-%S")
                echo "$risultati" > "report_${nome_programma}_${data_ora}.txt"
                yad --info --text="Report salvato come: report_${nome_programma}_${data_ora}.txt"
            fi
        fi
        continue
    fi
    
    # Estrai valori dal form
    nome_programma=$(echo "$scelta" | cut -d'|' -f1)
    avanzata=$(echo "$scelta" | cut -d'|' -f2)
    
    if [ -z "$nome_programma" ]; then
        yad --warning --text="Inserire un nome programma!"
        continue
    fi
    
    # Mostra progress bar
    (
        echo "10" ; echo "# Avvio scansione per: $nome_programma" ; sleep 0.5
        echo "20" ; echo "# Controllo pacchetti APT..." ; sleep 0.3
        echo "40" ; echo "# Controllo pacchetti Snap..." ; sleep 0.3
        echo "60" ; echo "# Controllo pacchetti Flatpak..." ; sleep 0.3
        echo "80" ; echo "# Controllo altre installazioni..." ; sleep 0.3
        echo "100" ; echo "# Analisi completata!" ; sleep 0.2
    ) | yad --progress \
        --title="Scansione in corso..." \
        --text="Analizzo l'installazione del programma" \
        --percentage=0 \
        --auto-close \
        --width=400
    
    # Esegui analisi
    risultati=$(analizza_installazione "$nome_programma")
    
    # Mostra risultati
    scelta_risultato=$(echo "$risultati" | yad --text-info \
        --title="📊 RISULTATI: $nome_programma" \
        --text="$risultati" \
        --width=750 --height=550 \
        --button="🔄 Nuova ricerca:0" \
        --button="💾 Salva report:1" \
        --button="📋 Copia info:2" \
        --button="🔍 Dettagli file:3" \
        --button="🚪 Esci:4" \
        --fontname="Monospace 10")
    
    case $? in
        1)  # Salva report
            data_ora=$(date "+%Y-%m-%d_%H-%M-%S")
            echo "=== REPORT INSTALLAZIONE ===" > "report_${nome_programma}_${data_ora}.txt"
            echo "Data: $(date)" >> "report_${nome_programma}_${data_ora}.txt"
            echo "Programma: $nome_programma" >> "report_${nome_programma}_${data_ora}.txt"
            echo "" >> "report_${nome_programma}_${data_ora}.txt"
            echo "$risultati" | sed 's/<[^>]*>//g' >> "report_${nome_programma}_${data_ora}.txt"
            yad --info --text="✅ Report salvato come:\nreport_${nome_programma}_${data_ora}.txt"
            ;;
        2)  # Copia info
            echo "$risultati" | sed 's/<[^>]*>//g' | xclip -selection clipboard
            yad --info --text="✅ Informazioni copiate negli appunti!"
            ;;
        3)  # Dettagli file
            # Cerca file principali
            file_principali=$(find /usr/bin /usr/local/bin /snap/bin ~/.local/bin -name "*$nome_programma*" 2>/dev/null | head -5)
            if [ ! -z "$file_principali" ]; then
                echo "File trovati:" > /tmp/file_trovati.txt
                echo "$file_principali" >> /tmp/file_trovati.txt
                yad --text-info --title="File del programma" \
                    --filename=/tmp/file_trovati.txt \
                    --width=600 --height=300
            else
                yad --warning --text="Nessun file eseguibile trovato"
            fi
            ;;
        4)  # Esci
            exit 0
            ;;
    esac
done
