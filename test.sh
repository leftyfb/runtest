#!/bin/bash
d=$(date +%F-%H-%M-%S)
kernel="$(uname -r)-$(uname -v|awk '{print $1}'|sed 's/#//g')"
CPUs=$(lscpu|grep ^"CPU(s)"|awk '{print $2}')
MEM=$(free -h|grep "Mem:"|awk '{print $2}')
dmesgtmp=/tmp/dmesg.tmp
pstmp=/tmp/ps.tmp
testname="pingtest"
packagename=stress-ng
packageversion=$(apt-cache policy $packagename|grep Installed|awk '{print $2}')
sortname="$testname/$packageversion"
mainlog=mainlog.log

setlogitems(){
 if [ -n "$note" ] ;then
  testlogitems="$d,$testname,$duration,$packageversion,$CPUs,$MEM,$note"
 else
  testlogitems="$d,$testname,$duration,$packageversion,$CPUs,$MEM"
 fi
}

testcmd(){
 echo "Running test..."
 SECONDS=0
 ping -c3 192.168.1.123
# /usr/lib/plainbox-provider-checkbox/bin/memory_stress_ng
# sudo /usr/lib/plainbox-provider-checkbox/bin/memory_test
# sudo /usr/lib/plainbox-provider-checkbox/bin/disk_stress_ng /dev/sda --base-time 240 --really-run
# sudo /home/ubuntu/disk_stress_ng.bin /dev/sda --base-time 240 --really-run
 echo "Test Complete"
}

mktestdir(){
if [ ! -d $sortname ] ; then
	mkdir -p $sortname
fi
}

getdate(){
 date +%F-%H-%M-%S
}

confirm(){
    echo -e "$1\nContinue? [N/y]"
    read -sN1 confirm
    if [ "${confirm}" = "" ]; then
      exit 1
    elif [ "${confirm}" = "y" -o "${confirm}" = "Y" ]; then
      true
    elif [ "${confirm}" = "n" -o "${confirm}" = "N" ]; then
      exit 1
    else
      exit 1
    fi
}

checkscreen(){
if [ -z "$STY" ]; then 
 confirm "You are not running in screen"
fi
}

purge_kernlog(){
 sudo cp /var/log/kern.log /var/log/kern.$d.log
 logheader /var/log/kern.log > /dev/null
}

process_kernlog(){
 cp -v /var/log/kern.log $sortname/$1-$d.kern.log
}

process_dmesg(){
 # Find dmesg log last touched
 local fs1=$(cat dmesg1.log |wc -l)
 local fs2=$(cat dmesg2.log |wc -l)
 if [ "$fs2" -gt "$fs1" ] ; then
      mv -v dmesg2.log $sortname/$1-$d.dmesg
      sleep 1
      chkrm dmesg1.log
 else 
      mv -v dmesg1.log $sortname/$1-$d.dmesg
      sleep 1
      chkrm dmesg2.log
 fi
}

process_ps(){
 # Find ps log last touched
 local fs1=$(cat ps1.log |wc -l)
 local fs2=$(cat ps2.log |wc -l)
 if [ "$fs2" -gt "$fs1" ] ; then
      mv -v ps2.log $sortname/$1-$d.ps
      sleep 1
      chkrm ps1.log
 else 
      mv -v ps1.log $sortname/$1-$d.ps
      sleep 1
      chkrm ps2.log
 fi
}

process_logs(){
 mktestdir
 if [ $1 = "FAIL" ] ; then
  note=$(grep ^"Note: " $mainlog|sed 's/Note: //g')
  d=$(grep ^"Date: " $mainlog|sed 's/Date: //g')
  kernel=$(grep "kernel = " $mainlog|awk '{print $3}')
  if [ $note = "" ] ; then
   readnote
  else
   setlogitems
  fi
 fi
 process_mainlog $1
 process_kernlog $1
 process_dmesg $1
 process_ps $1 
}

logheader(){
 echo "Test Name: $testname" | sudo tee $1
 echo "Date: $d" | sudo tee -a $1
 echo "Kernel: $kernel" | sudo tee -a $1
 echo "Note: $note" | sudo tee -a $1
}

process_mainlog(){
 echo -e "\n================================================================\n
 Test Name: $testname
 Hostname = $HOSTNAME
 Kernel = $kernel
 Package Name: $packagename
 Package Version: $packageversion
 CPU Cores: $CPUs
 Memory: $MEM
 Test started: $d
 Test ended: $(getdate)\n
 Result: $1 
 ================================================================"|sudo tee -a $mainlog
 mv -v $mainlog $sortname/$1-$d.log
}

cleanup(){
 echo "We found logs from a previous test.."
 chkrm $pstmp
 chkrm $dmesgtmp 
 read -p "Do you want to keep these logs? [Y/n]" -N1
 if [[ $REPLY =~ ^[Nn]$ ]] ; then
  deletelogs 
 else
  process_logs FAIL
  echo "FAIL,$testlogitems" >> log
 fi
 confirm "Previous logs cleaned up"
} 

deletelogs(){
  for i in $mainlog ps1.log ps2.log dmesg1.log dmesg2.log
   do
    chkrm $i
  done
}

chkrm(){
 if [ -f $1 ]; then
  sudo rm -v $1
 fi
}


forkps(){
 echo "1" > $pstmp
 while grep -q "1" $pstmp 2>/dev/null
	 do 
		 logheader ps1.log >/dev/null
		 ps -ax >/dev/null|sudo tee -a ps1.log 
		 sleep 5 
 		 logheader ps2.log > /dev/null
		 ps -ax >/dev/null|sudo tee -a ps2.log
		 sleep 5
 done
}

forkdmesg(){
 echo "1" > $dmesgtmp
 while grep -q "1" $dmesgtmp 2>/dev/null
	 do 
		 logheader dmesg1.log > /dev/null
		 dmesg >/dev/null|sudo tee -a dmesg1.log
		 sleep 5 
		 logheader dmesg2.log > /dev/null
		 dmesg >/dev/null|sudo tee -a dmesg2.log
		 sleep 5
 done

}

readnote(){
 read -N1 -p "Would you like to add a note for this test? [N/y] "
 echo
 if [[ $REPLY =~ ^[Yy]$ ]]
 then
     read -p "Note: " note
 echo
     setlogitems
 fi
}

if ls *.log 1> /dev/null 2>&1 ; then
	cleanup
fi

echo -e "\e[1;93m===========================================================\n"
echo -e "\e[93mTest Name: \t\t\e[94m$testname"
echo -e "\e[93mHostname: \t\t\e[94m$HOSTNAME"
echo -e "\e[93mKernel: \t\t\e[94m$(uname -r)"
echo -e "\e[93mPackage: \t\t\e[94m$packagename"
echo -e "\e[93mPackage Version: \t\e[94m$packageversion"
echo -e "\e[93mCPU Cores: \t\t\e[94m$CPUs"
echo -e "\e[93mMemory: \t\t\e[94m$MEM"
echo -e "\e[93mDate: \t\t\t\e[94m$d"
echo 
echo -e "\e[93m===========================================================\n"
echo -e "\e[0mAbout to run test ..."
readnote
confirm "Run test?"
checkscreen
purge_kernlog
logheader $mainlog > /dev/null
forkdmesg &
forkps &
testcmd|sudo tee -a $mainlog
duration=$SECONDS
duration=$(date -u -d @${SECONDS} +%T)
setlogitems
chkrm $dmesgtmp
chkrm $pstmp
sleep 6
process_logs PASS
echo "PASS,$testlogitems" >> log
