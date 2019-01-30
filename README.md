# pepper_os

Building over Gentoo Prefix, and over that ros-overlay, plus anything extra
needed to make Pepper robots able to do more with the latest available software.

# Build

```bash
docker build --network host -f Dockerfile -t pepper_os .
```

# Run

```bash
docker run -it -h pepper awesomebytes/pepper_os
```

# Buildfarm

Link: https://dev.azure.com/ROOGP/ROOGP_CI/_build

# How to deploy on your robot

Go to the [releases](https://github.com/awesomebytes/pepper_os/releases) section and download the latest release of the OS. It is divided in parts of <1GB, total ~4GB. For example:

```bash
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2019-01-30T04at52plus00at00/pepper_os_ros-kinetic-x86_2019-01-30T04at52plus00at00_not_full_rebuild.tar.gz.part-00 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2019-01-30T04at52plus00at00/pepper_os_ros-kinetic-x86_2019-01-30T04at52plus00at00_not_full_rebuild.tar.gz.part-01 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2019-01-30T04at52plus00at00/pepper_os_ros-kinetic-x86_2019-01-30T04at52plus00at00_not_full_rebuild.tar.gz.part-02 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2019-01-30T04at52plus00at00/pepper_os_ros-kinetic-x86_2019-01-30T04at52plus00at00_not_full_rebuild.tar.gz.part-03 &
aria2c -x 10 https://github.com/awesomebytes/pepper_os/releases/download/release%2F2019-01-30T04at52plus00at00/pepper_os_ros-kinetic-x86_2019-01-30T04at52plus00at00_not_full_rebuild.tar.gz.part-04 &
wait
echo "Done with all the downloads!"
```


Now merge together the files, you can use the instruction from the release notes:
```bash
cat pepper_os_ros-kinetic-x86_*.tar.gz.part-* > pepper_os_ros-kinetic-x86.tar.gz
```


Now extract in your (clean, e.g. `rm -rf * *.` done on the home folder, you may want to back up everything first if you are to do that) robot in one command (avoiding copying the file and then extracting):

```bash
cat pepper_os_ros-kinetic-x86.tar.gz | ssh nao@192.168.1.12 "tar xzf - -C /home/nao"
```

