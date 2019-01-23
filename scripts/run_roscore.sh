#!/bin/bash

date >> /home/nao/.run_roscore.log
echo "Executing $0 $1" >> /home/nao/.run_roscore.log

# Make sure the gentoo prefix will be picked up
# Check if the link exists in /tmp/gentoo
if [ ! -L /tmp/gentoo ]; then
  echo "Softlink to this Gentoo Prefix in /tmp/gentoo does not exist, creating it..." >> /home/nao/.run_roscore.log
  cd /tmp
  ln -s /home/nao/gentoo gentoo
fi

source /home/nao/.bash_profile
export PATH=/tmp/gentoo/usr/bin:$PATH


# Run roscore on the provided IP
# as first argument

export ROS_IP=$1
export ROS_MASTER_URI=http://$ROS_IP:11311
echo "Will run roscore with IP: $ROS_IP" >> /home/nao/.run_roscore.log

# Kill any roscore that was running before
echo "Killing roscore if any is running..." >> /home/nao/.run_roscore.log
killall roscore || true

echo "Running new roscore on: $ROS_IP" >> /home/nao/.run_roscore.log
# Trick 1: To avoid log buffering in roscore (python program)
export PYTHONUNBUFFERED=1
nohup roscore &
# Trick 2: to get the output to the file I want instead of nohup.out
mv nohup.out .roscore.out

echo "Executed, check if running:" >> /home/nao/.run_roscore.log
ps aux | grep bin/roscore | grep -v grep >> /home/nao/.run_roscore.log

echo "Done" >> /home/nao/.run_roscore.log