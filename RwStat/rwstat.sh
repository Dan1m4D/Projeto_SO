#!/bin/bash

# Mensagem de uso, é mostrada caso o comando seja inicializado com argumentos inválidos
usage() {
    echo " ╭─────────────────────────────────────────────────────────────╮" 
    echo -e " │ \e[4mUsagem:\e[24m                                                     │" 
    echo " │   -> $0 [argumentos] <num. segundos a analisar>    │"
    echo " ╰─────────────────────────────────────────────────────────────╯" 
    echo " ╭─────────────────────────────────────────────────────────────╮" 
    echo -e " │ \e[4mArgumentos:\e[24m                                                 │"
    echo " │   -> -c <nome do processo (regex)>                          │" 
    echo " │   -> -s <data inicial>                                      │" 
    echo " │   -> -e <data final>                                        │" 
    echo " │   -> -u <nome do utilizador (regex)>                        │"
    echo " │   -> -m <PID mínimo>                                        │" 
    echo " │   -> -M <PID máximo>                                        │" 
    echo " │   -> -p <Máximo número de entradas na tabela>               │" 
    echo " │   -> -r (inverter a ordem da tabela)                        │" 
    echo " │   -> -w (ordenar a tabela pelo rate de write)               │" 
    echo " │   -> -h (help)                                              │" 
    echo " ╰─────────────────────────────────────────────────────────────╯" 
    1>&2; exit 1;
}

# Função de geração da maior parte do array de dados
function generateDataArr() {
    declare -n dataArray="$1"
    # Número de processos no array
    procIdsCatched=${#PIdVector[@]}

    # Gerar o array de dados de cada processo
    # for i = [0, 1, ..., procIdsCatched-1]
    for i in $(seq 0 $(( procIdsCatched - 1 ))); do
        procPId=${PIdVector[$i]}
        
        # Ignorar os processos a que não se tem acesso (ou não existe) o ficheiro
        if ! [[ -f "/proc/${procPId}/io" ]]; then
                continue
        fi

        # Obter o número de bits lidos e escritos até agora
        procRead=($(sudo cat /proc/${procPId}/io | grep "rchar" | awk '{ print $2 }') )
        procWrite=($(sudo cat /proc/${procPId}/io | grep "wchar" | awk '{ print $2 }') )

        # Ignorar processos que não lêm nem escrevem 
        if [[ $procRead -eq 0  ]] && [[ $procWrite -eq 0 ]]; then
            continue
        fi
        
        # Ignorar as linhas com PId que não estão no conjunto específicadp
        if ( [[ "$m" -ne "0" ]] && [[ "${procPId}" -lt "$m" ]] ) || ( [[ "$M" -ne "0" ]] && [[ "${procPId}" -gt "$M" ]] ); then 
            continue
        fi
        
        procDate=($(ls -ld /proc/${procPId} | awk '{ print $6, $7, $8 }'))

        # Só compara os tempos se estes forem restringidos pelo utilizador 
        if [ "${s}" != "0" ] || [ "${e}" != "0" ];then
            dateProcess=$(date -d "${procDate[0]} ${procDate[1]} ${procDate[2]}" +%s)

            if [ "${s}" != "0" ];then
                dateStart=$(date -d "${s}" +%s)
                if [[ $dateProcess -le $dateStart ]]; then 
                    continue
                fi
            fi
            if [ "${e}" != "0" ];then
                dateEnd=$(date -d "${e}" +%s)
                if [[ $dateProcess -ge $dateEnd ]]; then 
                    continue
                fi
            fi
        fi

        procComm=($(sudo cat /proc/${procPId}/comm))
        procUser=($(stat --format '%U' /proc/${procPId}))

        procData[$maxProc, 0]=${procComm}
        procData[$maxProc, 1]=${procUser}
        procData[$maxProc, 2]=${procPId}
        procData[$maxProc, 7]=${procDate[@]}

        # Num total de processos analisados
        ((maxProc=maxProc+1))
        #fi
    done

    return
}

# Função que obtem os dados de leitura e escrita
function readWriteData() {
    local numProcMax=$1

    t1=$(date +%s%3N)

    for i in $(seq 0 $(( numProcMax - 1 ))); do

        procPId=${procData[$i, 2]}

        # Ignorar os processos a que não se tem acesso (ou não existe) o ficheiro
        if ! [[ -f "/proc/${procPId}/io" ]]; then
                continue
        fi

        procRead=($(sudo cat /proc/${procPId}/io | grep "rchar" | awk '{ print $2 }') )
        procWrite=($(sudo cat /proc/${procPId}/io | grep "wchar" | awk '{ print $2 }') )

        procData[$i, 5]=${procRead#-}
        procData[$i, 6]=${procWrite#-}
    done

    t2=$(date +%s%3N)
    # Calcular o tempo a esperar (tempo escolhido menos tempo gasto no primeiro for)
    sleepTime=$(echo | awk -v secs="$updateTime" -v t2="$t2" -v t1="$t1" 'BEGIN {print (secs*1000 - (t2-t1)) / 1000}')
    # Esperar o tempo especificado
    sleep ${sleepTime#-}

    # Reler o número de carateres lido/escrito por processo
    for i in $(seq 0 $(( numProcMax - 1 ))); do

        procPId=${procData[$i, 2]}

        # Ignorar os processos a que não se tem acesso (ou não existe) o ficheiro
        if ! [[ -f "/proc/${procPId}/io" ]]; then
                continue
        fi

        procRead=($(sudo cat /proc/${procPId}/io | grep "rchar" | awk '{ print $2 }') )
        procWrite=($(sudo cat /proc/${procPId}/io | grep "wchar" | awk '{ print $2 }') )

        procData[$i, 3]=${procRead#-}
        procData[$i, 4]=${procWrite#-}
    done

    # Fazer as médias de lida/escrita
    for i in $(seq 0 $(( numProcMax - 1 ))); do

        # Difrença entre as duas leituras
        numRead="$(( procData[$i, 3] - procData[$i, 5] ))"
        numWrite="$(( procData[$i, 4] - procData[$i, 6] ))"

        # Taxas lida/escrita
        numMedioRead="$(( numRead / updateTime ))"
        numMedioWrite="$(( numWrite / updateTime ))"

        # Atualiza-mos a escrita e lida total só por conveniência
        procData[$i, 3]=${numRead#-}
        procData[$i, 4]=${numWrite#-}
        procData[$i, 5]=${numMedioRead#-}
        procData[$i, 6]=${numMedioWrite#-}
    done

    return
}

# Função que ordena o array
function sortArray() {
    declare -n dataArray="$1"
    local numProcMax="$2"

    # Escolher qual index da dataArray para comparar (5 = taxa read | 6 = taxa write)
    sortN=5
    if [ "$w" -eq 1 ]; then
        sortN=6
    fi

    # Fazer bubble Sort no array
    for i in $(seq 0 $(( numProcMax - 1 ))); do
        for j in $(seq $i $(( numProcMax - 1 ))); do
            # Caso o valor da linha i < j
            if [[ "${dataArray[$i, $sortN]}" -lt "${dataArray[$j, $sortN]}" ]]; then
                # Copiar a linha i para temp
                for ((n = 0; n < 8; n++)); do
                    temp[$n]=${dataArray[$i, $n]}
                done
                # Copiar a linha j para i e a linha temp para j
                for ((m = 0; m < 8; m++)); do
                    dataArray[$i, $m]=${dataArray[$j, $m]}
                    dataArray[$j, $m]=${temp[$m]}
                done
            fi
        done
    done

    return
}

# Função que remove o resto dos processos baseado nos critérios escolhidos
function clearArray() {
    declare -n dataArray=$1
    declare -A tempArray
    local numProcs=$2
    local indexTemp="0"

    # for i = [0, 1, ..., numProcs-1]
    for i in $(seq 0 $(( numProcs - 1 ))); do

        # Ignorar as linhas que tenham rates Write/Read de 0
        if [[ "${dataArray[$i, 6]}" -eq 0 ]] || [[ "${dataArray[$i, 5]}" -eq 0 ]]; then 
            continue
        fi

        #  Colocar a linha do dataArray no tempArray, 
        # agora que sabemos que esta é importante
        for ((n = 0; n < 8; n++)); do
            tempArray[$indexTemp, $n]="${dataArray[$i, $n]}"
        done
        ((indexTemp=indexTemp+1))
    done

    # Clonar o array temporário para procData
    unset procData
    declare -gA procData
    for key in "${!tempArray[@]}"; do
        procData[$key]=${tempArray[$key]}
    done
    maxProc=${indexTemp}

    return
}

# Função que imprime o array no formato de tabela
function printArray() {
    declare -n local dataArray="$1"  # Cópia local de procData
    local start=0          # Número da linha inicial
    local increment=1      # Incremento (positivo ou negatívo)
    local end=$(( ${#dataArray[@]} / 8 )) # Número da linha final

    # Onde começar/acabar a tabela, caso "-r" seja definido
    if [ "$r" -eq 1 ]; then
        start=$(( end -1 )) # Começar no fim do array
        end="-1"        # Acabar no inicio do array
        increment="-1"      # Incrementar negatívamente
    fi

    # Se não existir nada no array final
    if [ "$end" -eq 0 ]; then    printf " ╭"
        printf "─%0.s" {1..84}
        printf "╮ \n"
        printf " │       Não foram encontrados nenhuns processos com os argumentos apresentados       │\n"

        printf " ╰"
        printf "─%0.s" {1..84}
        printf "╯ \n"
        return
    fi


    # Cabeçalho
    printf " ╭"
    printf "─%0.s" {1..115}
    printf "╮ \n"
    printf " │ %-18s %-18s %6s %13s %13s %10s %10s %18s │ \n" "COMM" "USER" "PID" "READB" "WRITEB" "RATER" "RATEW" "DATE"

    printf " ╰"
    printf "─%0.s" {1..115}
    printf "╯ \n ╭"
    printf "─%0.s" {1..115}
    printf "╮ \n"

    local printsShown="1"

    #for j in $(seq $start $end); do       
    for (( j = ${start} ; j != ${end} ; j = ${j} + ${increment} )); do

        printf " │ %-18s %-18s %6s %13s %13s %10s %10s %18s │ \n" "${dataArray[$j, 0]}" "${dataArray[$j, 1]}" "${dataArray[$j, 2]}" "${dataArray[$j, 3]}" "${dataArray[$j, 4]}" "${dataArray[$j, 5]}" "${dataArray[$j, 6]}" "${dataArray[$j, 7]}"
        
        # Determinar o fim da tabela caso "-p <int>" seja definido
        if [[ "$p" -eq "printsShown" ]];then
            break
        fi
        ((printsShown = printsShown + 1 ))
    done

    printf " ╰"
    printf "─%0.s" {1..115}
    printf "╯ \n"

    return
}

# ------------------------------------------
# ------------------_MAIN_------------------
# ------------------------------------------


# Default Values, podem ser sobreescritos pelo utilizador
c=".*"    # Regex para filtrar processos pelo seu COMM
u=".*"    # Regex para filtrar processos pelo seu USER
s="0"     # Data mínima inicial dos processos
e="0"     # Data máxima inicial dos processos
m=0      # PID mínimo dos processos
M=0      # PID máximo dos processos
p=0      # Num máximo de processos a mostrar
w=0      # Ordenar a tabela pela taxa de escrita
r=0      # Ordenar a tabela inversamente

maxProc=0

declare -A procData

# Obter opções do comando incial    
while getopts "c:s:e:u:m:M:p:wrh" commArg; 
do
    case "${commArg}" in
        # Regex a aplicar sobre o nome do processo
        c)
            c=${OPTARG}
            ;;
        #  Regex a aplicar sobre o nome do  
        # utilizador do processo
        u)
            u=${OPTARG}
            ;;
        # Data mínima inicial do processo
        s)
            s=${OPTARG}
            (( ${#s} != 0 )) || usage
            ;;  
        # Data máxima inicial do processo
        e)
            e=${OPTARG}
            (( ${#e} != 0 )) || usage
            ;;
        # Número mínimo do ID do processo
        m)
            m=${OPTARG}
            ((m > 0)) || usage
            ;;
        # Número máximo do ID do processo
        M)
            M=${OPTARG}
            ((M > 0)) || usage
            ;;
        # Número de processos a mostrar na tabela
        p)
            p=${OPTARG}
            ((p > 0 || p < 1000)) || usage
            ;;
        # Ordenar por leitura (0) ou escrita (1)
        w)
            w=1
            ;;    
        #  Ordenar pelo número maior (0) 
        # ou pelo número menor (1)
        r)
            r=1
            ;;
        # Mostrar a usagem caso seja requesitado
        h)
            usage
            ;;
        #  Mostrar a usagem caso seja m
        # intruduzidas opções inválidas
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# Tempo entre as duas leituras das taxas read/write
updateTime="${*}"

if [[ "$M" -ne "0" ]] && [[ "$m" -ne "0" ]]; then
    # Asserta que "M" é maior ou igual que "m"
    ((M >= m)) || usage
fi
if [ "$s" != "0" ] && [ "$e" != "0" ];then
    # Asserta que "s" é menor ou igual a "e"
    (( $(date -d "${s}" +%s) <= $(date -d "${e}" +%s) )) || usage
fi

#  Testar se o ultimo argumento (segundos entre leituras)
# não foi utilizado, ou é inválido
if [[ "$*" -eq "" ]] || [[ "${updateTime}" =~ '^[0-9]+$'  ]] || 
   [[ "${updateTime}" -lt 1 ]] || [[ "${updateTime}" -gt 1000 ]]; then
    usage
fi


  #         ps com PID, user, comm | ignorar cabeçalho |
PIdVector=($(sudo ps -Ao pid,user,comm | tail -n +2 | 
    awk -v userName="$u" -v comName="$c" '$3~comName && $2~userName { print $1 }' ))
  #    user e comm filtrados com regex                  output só os PIDs selecionados




#PIdVector=($(pgrep -P 1))


# Gerar a maior parte do array de informação
generateDataArr procData

# Ler e fazer a média das taxas read/write
readWriteData maxProc

# Remover as entradas do array que não interessam
clearArray procData maxProc

# Ordenar o array
sortArray procData maxProc

# Apresentar o array na forma tabela
printArray procData


