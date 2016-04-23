#!/bin/sh

##### global variables ####

# temporary file which stores ping results
pingFile="/tmp/pingFile"
# number of ping to send to each machine
pingNumber="2"
# maximum time to wait for a ping reply
pingTimeout="2"
# account used to halt Windows computers
  # local account, "\" must be replaced by "/", could not make it work with modern username@localhost
winAccount="localhost/administrateur"
  # domain account
#winAccount="domain/administrator"
# account used to halt Unix computers (SSH)
unixAccount="root"

##### functions #####

showHelp () {
  echo "Usage :"
  echo "$0 start | ping | stop file.csv"
  echo
  echo "Wake on Lan function needs \"wakeonlan\" package."
  echo "Halting Windows machines needs \"samba-common-bin\"."
  echo "Halting Unix machines package \"sshpass\"."
  echo
  echo "Each line of the CSV file must follow this format:"
  echo "mac_adress,IP_address,fake_IP_address,OS,comment"
  echo
  echo "What are these fields:"
  echo "- mac_address: MAC address of the remote machine, used for"
  echo "  wake on lan"
  echo "- IP_address: IP address of the remote machine, used to"
  echo "  test if it is up"
  echo "- broadcast_IP_address: broadcast IP if the machine is on the"
  echo "  same subnet, or see below if it is on another subnet"
  echo "- OS: used to shutdown the remote machine (possible values"
  echo "  are \"unix\" for SSH and \"windows\" for RPC)"
  echo "- comment: anything you want, usually name of the remote machine"
  echo
  echo "Lines starting with \"#\" are printed during execution to help you"
  echo "follow script execution."
  echo "Blank lines are forbidden."
  echo
  echo "Best solution if you want to wake up many machines on another subnet:"
  echo "- magic packages must be sent to a unused IP address of this subnet,"
  echo "  which is done by setting this IP as the fake_IP_address in the CSV"
  echo "  file"
  echo "- the router connected to this subnet must have an ARP entry matching"
  echo "  this IP address and the MAC address FF:FF:FF:FF:FF:FF (if the router"
  echo "  is running FreeBSD, it could be done with a cron task executing"
  echo "  \"arp -s fake_IP_address ff:ff:ff:ff:ff:ff\")"
}

checkFile () {
  n=1
  while IFS= read -r line
  do
    # we do not check comment lines
    if echo "$line" | grep -v "^#" > /dev/null; then
      # check each line's number of fields
      if [ "$(echo "$line" | grep -o "," | wc -l)" != "4" ]; then
        echo "Line $n of $csvFile is not valid: aborting."
        exit 1
      # check what OS is present, in case of a shutdown request
      elif echo "$line" | cut -d "," -f 4 | grep "win" > /dev/null; then
        askWinPwd="true"
      elif echo "$line" | cut -d "," -f 4 | grep "unix" > /dev/null; then
        askUnixPwd="true"
      fi
    fi
  n=$((n+1))
  done < "$csvFile"
}

wolMachines () {
  # check if required command is available
  if ! command -v "wakeonlan" > /dev/null 2>&1; then
    echo "Command \"wakeonlan\" is not available."
    exit 1
  fi

  while IFS= read -r line
  do
    # we print comment lines
    if echo "$line" | grep "^#" > /dev/null; then
      echo "$line"
    else
      macAddress=$(echo "$line" | cut -d "," -f 1)
      IPAddress=$(echo "$line" | cut -d "," -f 2)	
      broadcastAddress=$(echo "$line" | cut -d "," -f 3)
      name=$(echo "$line" | cut -d "," -f 5)
      # magic packets are sent 3 times to be sure
      for i in 1 2 3; do
        wakeonlan -i "$broadcastAddress" "$macAddress" > /dev/null
      done
      echo "$name ($macAddress) : 3 magic packets sent to $broadcastAddress"
    fi
  done < "$csvFile"
}

pingOneMachine () {
  ping -n -c "$pingNumber" -q -W "$pingTimeout" "$1" > /dev/null
  if [ "$?" = "0" ]; then
    echo "$2: OK" >> "$3"
  else
    echo "$2 does not answer" >> "$3"
  fi
}

pingMachines () {
  # check that machines are started
  while IFS= read -r line
  do
    # we avoid comment lines
    if echo "$line" | grep -v "^#" > /dev/null; then
      IPAddress=$(echo "$line" | cut -d "," -f 2)
      name=$(echo "$line" | cut -d "," -f 5)
      # allow simultaneous pinging of many machines
      pingOneMachine "$IPAddress" "$name" "$pingFile" &
    fi
  done < "$csvFile"
  waitTime=$((pingNumber * pingTimeout + 2))
  echo "Ping sended, waiting $waitTime seconds for replies..."
  sleep "$waitTime"
  sort < "$pingFile"
  rm "$pingFile"
}

askPassword () {
  # asking remote passwords outside while loop to avoid stty errors
  echo
  if [ "$1" = "win" ]; then
    echo
    echo "Please give password of user \"$winAccount\" for windows boxes :"
    stty -echo
    read -r winPassword
    stty echo
  elif [ "$1" = "unix" ]; then
    echo "Please give password of user \"$unixAccount\" for Unix boxes :"
    stty -echo
    read -r unixPassword
    stty echo
  fi
}

halt () {
  echo "NOT WELL TESTED"
  echo "Warning: other users on this box can easily spy your passwords!"
  echo "Press any key to continue."
  read -r fake
  if [ "$askWinPwd" = "true" ]; then
    askPassword "win"
  fi
  if [ "$askUnixPwd" = "true" ]; then
    askPassword "unix"
  fi
  while IFS= read -r line
  do
    # we print comment lines
    if echo "$line" | grep "^#" > /dev/null; then
      echo "$line"
    else
      IPAddress=$(echo "$line" | cut -d "," -f 2)
      OS=$(echo "$line" | cut -d "," -f 4)
      name=$(echo "$line" | cut -d "," -f 5)

      if [ "$OS" = "win" ]; then
        # check if required command is available
        if ! command -v "net" > /dev/null 2>&1; then
            echo
            echo "Command \"net\" is not available, skipping \"$name\""
        else
          net rpc -S "$IPAddress" -U "$winAccount"%"$winPassword" shutdown -t 1 -f
        fi

      elif [ "$OS" = "unix" ]; then
        # check if required command is available
        if ! command -v "sshpass" > /dev/null 2>&1; then
          echo "Command \"sshpass\" is not available, skipping \"$name\""
        else
          sshpass -p "$unixPassword" ssh "$unixAccount"@"$IPAddress" 'poweroff'
          # if you want to bypass host verification
          # sshpass -p "$unixPassword" ssh -o StrictHostKeyChecking=no "$unixAccount"@"$IPAddress" 'poweroff'
        fi
      else
        echo "\"$OS\" is not recognized as OS, skipping \"$name\""
      fi
    fi
  done < "$csvFile"
}

###### main program ######

if [ "$#" != "2" ]; then
  showHelp
  exit 1
fi

csvFile="$2"

if ! [ -r "$csvFile" ]; then
  echo "CSV file not readable (maybe missing ?)"
  exit 1
fi

checkFile

case "$1" in
  start) wolMachines;;
  ping) pingMachines;;
  stop) halt;;
  *) showHelp;;
esac

exit
