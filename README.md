# pepper_os

[![Build Status](https://dev.azure.com/ROOGP/ROOGP_CI/_apis/build/status/awesomebytes.pepper_os?branchName=master)](https://dev.azure.com/ROOGP/ROOGP_CI/_build?definitionId=1&_a=summary)

Building over [Gentoo Prefix](https://github.com/awesomebytes/gentoo_prefix_ci_32b), over that [ros-overlay](https://github.com/awesomebytes/ros_overlay_on_gentoo_prefix_32b/), plus anything extra
needed to make Pepper robots able to do more with the latest available software. The base image is the
raw Pepper hard disk image.

Pre-compiled software includes:
* ROS Kinetic (ROS desktop + navigation stack + many others) ([274 packages list](ROS_package_list.md))
* Latest Python 2.7.17 with a lot of libraries like dlib, Theano, OpenCV, Tensorflow, numpy ([255 packages list](PIP_package_list.md))
* All the necessary dependencies that make it possible to build it thanks to Gentoo Prefix (latest GCC, latest CMake, etc) ([767 packages list](GENTOO_package_list.md))

# How to deploy on your robot

Go to the [releases](https://github.com/awesomebytes/pepper_os/releases) section and download the latest release of the OS titled "Pepper OS based on Gentoo Prefix and ROS" (you can also use the ones tagged as _not full rebuild_ in case there hasn't been a successful built of the full rebuild for a while for some reason). It is divided in parts of <1GB, total ~5GB. For example:

```bash
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2020-02-05T19at34plus00at00/pepper_os_ros-kinetic-x86_2020-02-05T19at34plus00at00.tar.gz.part-00 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2020-02-05T19at34plus00at00/pepper_os_ros-kinetic-x86_2020-02-05T19at34plus00at00.tar.gz.part-01 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2020-02-05T19at34plus00at00/pepper_os_ros-kinetic-x86_2020-02-05T19at34plus00at00.tar.gz.part-02 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2020-02-05T19at34plus00at00/pepper_os_ros-kinetic-x86_2020-02-05T19at34plus00at00.tar.gz.part-03 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2020-02-05T19at34plus00at00/pepper_os_ros-kinetic-x86_2020-02-05T19at34plus00at00.tar.gz.part-04 &
wait
echo "Done with all the downloads!"
```


Now merge together the files, you can use the instruction from the release notes:
```bash
cat pepper_os_ros-kinetic-x86_*.tar.gz.part-* > pepper_os_ros-kinetic-x86.tar.gz
```

**WARNING** You may want to empty the home folder of your robot, after a backup of course, before doing the next step. This includes hidden files (starting with `.`). You can do `rm -rf * .*`.
Extracting this .tar.gz will write on a new folder called `gentoo`, where most of the stuff will reside. But it will also write a new `.bash_profile`, and a new `.local` folder with all Python libraries. It will also overwrite
your `~/naoqi/preferences/autoload.ini` with a script that will boot roscore on your next reboot of the robot.

Now extract in your robot in one command (avoiding copying the file and then extracting):

```bash
cat pepper_os_ros-kinetic-x86.tar.gz | ssh nao@192.168.1.12 "tar xzf - -C /home/nao"
```

Note that the `gentoo` folder uncompressed weights ~8GB and `.local` ~850MB.


# Build it yourself

In case you want to modify/fix/work on anything...

Takes 6h on the build farm (2core 2.2GHz), 3h in a faster machine (8core 3.6GHz).

```bash
docker build --network host -f Dockerfile -t pepper_os .
```

You can speed it up by using the cache of the latest version from the CI (5.3GB download though):

```bash
docker pull awesomebytes/pepper_os_image
docker build --network host -f Dockerfile --cache-from awesomebytes/pepper_os_image -t pepper_os .
```

# Run just the docker image

From the CI:

```bash
docker run -it -h pepper awesomebytes/pepper_os_image
```

If you built your own:

```bash
docker run -it -h pepper pepper_os
```

# Buildfarm
[![Build Status](https://dev.azure.com/ROOGP/ROOGP_CI/_apis/build/status/awesomebytes.pepper_os?branchName=master)](https://dev.azure.com/ROOGP/ROOGP_CI/_build?definitionId=1&_a=summary)

Link: https://dev.azure.com/ROOGP/ROOGP_CI/_build

