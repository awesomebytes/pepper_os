FROM awesomebytes/pepper_2.5.5.5

USER nao
WORKDIR /home/nao

RUN cat /proc/cpuinfo; cat /proc/meminfo; df -h

# Download and extract the latest Gentoo Prefix + ROS desktop image
RUN last_desktop_url=`curl -s -L https://github.com/awesomebytes/ros_overlay_on_gentoo_prefix_32b/releases | grep -m 1 "ROS Melodic desktop" | cut -d '"' -f2 | xargs -n 1 printf "http://github.com%s\n"`; \
curl -s -L $last_desktop_url | grep download/release | cut -d '"' -f2 | xargs -n 1 printf "https://github.com%s\n" | xargs -n 1 curl -O -L -s &&\
    cat gentoo_on_tmp* > gentoo_on_tmp.tar.gz &&\
    rm gentoo_on_tmp*.part* &&\
    tar xf gentoo_on_tmp.tar.gz &&\
    rm gentoo_on_tmp.tar.gz

# Fix permissions of tmp
USER root
RUN chmod a=rwx,o+t /tmp
USER nao


# Prepare environment to run everything in the prefixed shell
RUN cd /tmp && ln -s /home/nao/gentoo gentoo &&\
    cp /etc/group /tmp/gentoo/etc/group || true &&\
    cp /etc/passwd /tmp/gentoo/etc/passwd || true
# To make sure everything builds and reports i686 we do this trick
RUN sed -i 's/env -i/linux32 env -i/' /tmp/gentoo/executeonprefix
# To allow the use of the $EPREFIX variable
RUN sed -i 's/SHELL=$SHELL"/SHELL=$SHELL EPREFIX=$EPREFIX"/' /tmp/gentoo/executeonprefix
# Note that no variables exposed from this Dockerfile will work on the
# RUN commands as they will be evaluated by the internal executeonprefix script

# And now switch the shell so every RUN command is executed in it
SHELL ["/tmp/gentoo/executeonprefix"]

# Let's make the compilations faster when possible
# Substitute the default -j2 with -j<NUM_CORES/2>
RUN sed -i -e 's/j1/j'"$((`grep -c \^processor \/proc\/cpuinfo` / 2))"'/g' $EPREFIX/etc/portage/make.conf
# Add extra jobs if we have enough CPUs
RUN sed -i 's/EMERGE_DEFAULT_OPTS=.*//' $EPREFIX/etc/portage/make.conf &&\
    echo "EMERGE_DEFAULT_OPTS=\"--jobs $((`grep -c \^processor \/proc\/cpuinfo` / 2)) --load-average `grep -c \^processor \/proc\/cpuinfo`\"" >> $EPREFIX/etc/portage/make.conf

# Force CHOST to build everything or 32b
RUN echo "CHOST=i686-pc-linux-gnu" >> $EPREFIX/etc/portage/make.conf

# Update our source repos first
# Because we may have previous patches that won't allow to do a sync...
RUN cd $EPREFIX/usr/local/portage && git clean -f && git reset --hard
# Now we can update
RUN emaint sync -a
# Prepare python
RUN emerge dev-python/pip
RUN pip install --user argparse

RUN echo "# required by ros-melodic/pcl_conversions-0.2.1::ros-overlay for navigation" >> $EPREFIX/etc/portage/package.accept_keywords &&\
    echo "=sci-libs/pcl-9999 **" >> $EPREFIX/etc/portage/package.accept_keywords

# Very ugly hack, need to fix this from whereve it came
# some packages are affected, others arent, weird
RUN cd /tmp/gentoo/opt &&\
    find ./ -type f -name *.pc -exec sed -i -e 's@/home/user/gentoo@/tmp/gentoo@g' {} \; &&\
    find ./ -type f -name *.cmake -exec sed -i -e 's@/home/user/gentoo@/tmp/gentoo@g' {} \;


RUN cd /tmp && git clone https://github.com/awesomebytes/pepper_os &&\
    cd pepper_os && git checkout melodic && cd .. &&\
    mkdir -p /tmp/gentoo/etc/portage/patches/ros-melodic &&\
    cp -r pepper_os/patches/* /tmp/gentoo/etc/portage/patches/ros-melodic &&\
    rm -rf pepper_os

# Navigation needs it becuase of ros-melodic/move_slow_and_clear
# Giving error: 
# RUN mkdir -p /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
#     cd /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
#     wget https://664126.bugs.gentoo.org/attachment.cgi?id=545428 -O gcc8.patch
RUN echo ">=sci-libs/pcl-1.10.0" >> /tmp/gentoo/etc/portage/package.mask
RUN echo "=sci-libs/pcl-1.9.1 **" >> /tmp/gentoo/etc/portage/package.accept_keywords
RUN emerge sci-libs/pcl

# Something pulls app-editors/xemacs-21.5.34-r5
# Meanwhile (if) https://bugs.gentoo.org/show_bug.cgi?id=712786 this is not fixed, we need to workaround
RUN cd $EPREFIX/usr/portage/app-editors/xemacs; find ./ -type f -exec sed -i -e 's/${D}/${ED}/g' {} \; &&\
    ebuild xemacs-21.5.34-r5.ebuild manifest

RUN emerge ros-melodic/robot_state_publisher \
    ros-melodic/geometry2 \
    ros-melodic/ros_control \
    ros-melodic/image_common \
    ros-melodic/image_transport_plugins \
    ros-melodic/diagnostics \
    ros-melodic/octomap_msgs \
    ros-melodic/tf2_geometry_msgs \
    ros-melodic/ros_numpy \
    ros-melodic/ddynamic_reconfigure_python


# Until https://github.com/ros-planning/navigation/pull/975 is merged and re-released (navfn and base_local_planner broken)
RUN mkdir -p $EPREFIX/etc/portage/patches/ros-melodic/base_local_planner &&\
    wget https://gist.githubusercontent.com/awesomebytes/ecf17fd753423d3041146ab8dc3f4311/raw/6cc2939156aa1b5f250ed939bbb7d9b80955f60b/base_local_planner_check_include_file.patch -O $EPREFIX/etc/portage/patches/ros-melodic/base_local_planner/base_local_planner_check_include_file.patch &&\
    mkdir -p $EPREFIX/etc/portage/patches/ros-melodic/navfn &&\
    wget https://gist.githubusercontent.com/awesomebytes/8069774e1c7c6bcb3ced5fea58f72992/raw/e9007ec0675388a3bd8c0182f9f5af2aa1045afb/navfn_check_include_file.patch -O $EPREFIX/etc/portage/patches/ros-melodic/navfn/navfn_check_include_file.patch


RUN emerge ros-melodic/navigation
RUN emerge ros-melodic/slam_gmapping
# Until 2020/04/17 we will need to manually unmask it as
# it is being deprecated, ros-overlay fix https://github.com/ros/ros-overlay/pull/976
RUN echo "dev-python/soappy" >> $EPREFIX/etc/portage/package.unmask
RUN emerge ros-melodic/cmake_modules \
    ros-melodic/naoqi_bridge_msgs \
    ros-melodic/perception_pcl \
    ros-melodic/pcl_conversions \
    ros-melodic/pcl_ros \
    ros-melodic/depthimage_to_laserscan \
    ros-melodic/rosbridge_suite
RUN emerge media-libs/portaudio \
    net-libs/libnsl \
    dev-cpp/eigen \
    media-libs/opus

# emerging pulseaudio asks for this
RUN echo ">=media-plugins/alsa-plugins-1.2.1 pulseaudio" >> $EPREFIX/etc/portage/package.use &&\
    echo "media-sound/pulseaudio -udev" >> $EPREFIX/etc/portage/package.use &&\
    emerge media-sound/pulseaudio


RUN echo ">=ros-melodic/mbf_simple_nav-0.2.5-r1 3-Clause" >> $EPREFIX/etc/portage/package.license &&\
    echo ">=ros-melodic/mbf_costmap_nav-0.2.5-r1 3-Clause" >> $EPREFIX/etc/portage/package.license &&\
    echo ">=ros-melodic/mbf_msgs-0.2.5-r1 3-Clause" >> $EPREFIX/etc/portage/package.license &&\
    echo ">=ros-melodic/mbf_abstract_nav-0.2.5-r1 3-Clause" >> $EPREFIX/etc/portage/package.license &&\
    emerge ros-melodic/move_base_flex


# Start building custom packages maintained by SoftBank Robotics
# Patches for libqi and libqicore
RUN mkdir -p /tmp/gentoo/etc/portage/patches/ros-melodic/naoqi_libqi
COPY patches/libqi-release.patch /tmp/gentoo/etc/portage/patches/ros-melodic/naoqi_libqi/libqi-release.patch
RUN mkdir -p /tmp/gentoo/etc/portage/patches/ros-melodic/naoqi_libqicore
COPY patches/libqicore-release.patch /tmp/gentoo/etc/portage/patches/ros-melodic/naoqi_libqicore/libqicore-release.patch
# Given upstream there is no support for libqi and libqicore for melodic with boost > 1.70
# We just take the kinetic one and patch it to be 'melodic'
# To be fair, this should be PR'ed to ros-overlay, or even better, adapt the library in melodic to accept all boosts
# COPY ebuilds/naoqi_libqi-2.5.0-r3.ebuild $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqi
# COPY ebuilds/naoqi_libqicore-2.3.1-r1.ebuild $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqicore
RUN wget https://gist.githubusercontent.com/awesomebytes/6e85653e5a81de34c0287c5ba4d2a236/raw/339e3a9171dddd589ea2fee3382138867028ee5e/naoqi_libqi-2.5.0-r3.ebuild -O $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqi/naoqi_libqi-2.5.0-r3.ebuild
RUN wget https://gist.githubusercontent.com/awesomebytes/0481f71d47c78cd46f0ea18e6639e21a/raw/506843a40d071db2071a025ad2c7249a766e332c/naoqi_libqicore-2.3.1-r1.ebuild -O $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqicore/naoqi_libqicore-2.3.1-r1.ebuild
RUN echo ">ros-melodic/naoqi_libqi-2.9" >> $EPREFIX/etc/portage/package.mask
RUN echo ">ros-melodic/naoqi_libqicore-2.9" >> $EPREFIX/etc/portage/package.mask
RUN ebuild $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqi/naoqi_libqi-2.5.0-r3.ebuild manifest
RUN ebuild $EPREFIX/usr/local/portage/ros-melodic/naoqi_libqicore/naoqi_libqicore-2.3.1-r1.ebuild manifest

#install libqi, libqicore and naoqi_driver
RUN emerge ros-melodic/naoqi_libqi ros-melodic/naoqi_libqicore ros-melodic/naoqi_driver


# #     ros-melodic/web_video_server \
# # CODEC_FLAG_GLOBAL_HEADER -> AV_CODEC_FLAG_GLOBAL_HEADER

# RUN pip install --user dlib
# As Pepper CPU has no AVX instructions
RUN git clone https://github.com/davisking/dlib &&\
    cd dlib &&\
    pip uninstall dlib -y &&\
    python setup.py install --user --no USE_AVX_INSTRUCTIONS

RUN pip install --user pysqlite
RUN pip install --user ipython
RUN pip install --user --upgrade numpy
RUN pip install --user scipy pytz wstool
# RUN pip install --user pytz
# RUN pip install --user wstool

RUN pip install --user Theano keras
RUN mkdir -p ~/.keras && \
echo '\
{\
    "image_data_format": "channels_last",\
    "epsilon": 1e-07,\
    "floatx": "float32",\
    "backend": "theano"\
}' > ~/.keras/keras.json


# # Tensorflow pending from our custom compiled one...
# # Which would be nice to automate too

RUN pip install --user h5py
RUN pip install --user opencv-python opencv-contrib-python

RUN pip install --user pyaudio SpeechRecognition nltk pydub

RUN pip install --user jupyter

RUN pip install --user https://github.com/awesomebytes/pepper_os/releases/download/upload_tensorflow-1.6.0/tensorflow-1.6.0-cp27-cp27mu-linux_i686.whl

RUN pip install --user xxhash

RUN pip install --user catkin_tools

RUN emerge ros-melodic/eband_local_planner

# FOR ROS MELODIC SOME MODIFICATION OF THIS WILL MOST PROBABLY BE NEEDED
# AT LEAST THE HARDCODING OF BLAS LIBRARY FOUND
# RUN cd /tmp/gentoo/usr/local/portage/ros-melodic/libg2o &&\
#     rm * &&\
#     wget https://raw.githubusercontent.com/ros/ros-overlay/b76f702b1acfa384f0c43679a1fe67ab4c1f99fe/ros-melodic/libg2o/libg2o-2016.4.24.ebuild &&\
#     wget https://raw.githubusercontent.com/ros/ros-overlay/b76f702b1acfa384f0c43679a1fe67ab4c1f99fe/ros-melodic/libg2o/metadata.xml &&\
#     ebuild libg2o-2016.4.24.ebuild manifest

# # # undocumented dependency of teb_local_planner
# cholmod-2.1.2 does not build with amd-2.4.6 and colamd-2.9.6
# cholmod is needed for suitesparse, and suitesparse is needed on libg2o
RUN echo ">=sci-libs/amd-2.4.6" >> $EPREFIX/etc/portage/package.mask &&\
    echo ">=sci-libs/colamd-2.9.6" >> $EPREFIX/etc/portage/package.mask &&\
    emerge sci-libs/suitesparse

RUN cd /tmp/gentoo/usr/lib/cmake/Qt5Gui; find ./ -type f -exec sed -i -e 's@/home/user@/tmp@g' {} \;
RUN emerge ros-melodic/libg2o

RUN cd /tmp/gentoo/etc/portage/patches/ros-melodic &&\
    mkdir -p teb_local_planner &&\
    cd teb_local_planner &&\
    wget https://gist.githubusercontent.com/awesomebytes/0e84ce3539cdbe6d8013a75f17de34a1/raw/c72c8d4f7d307e553629f18dab1c11d184e5295d/0001-Adapt-for-Gentoo-Prefix-on-tmp-gentoo.patch

RUN emerge ros-melodic/teb_local_planner
RUN emerge ros-melodic/dwa_local_planner
# Workaround
RUN cd /tmp/gentoo/usr/local/portage/ros-melodic/sbpl_lattice_planner &&\
    rm Manifest && \
    ebuild sbpl*.ebuild manifest
RUN emerge ros-melodic/sbpl_lattice_planner

RUN EXTRA_ECONF="--enable-pulse" emerge media-libs/gst-plugins-good
RUN emerge media-plugins/gst-plugins-opus \
    media-plugins/gst-plugins-v4l2 \
    media-plugins/gst-plugins-jpeg \
    media-plugins/gst-plugins-libpng \
    media-plugins/gst-plugins-lame \
    media-plugins/gst-plugins-x264 \
    media-plugins/gst-plugins-x265

# RUN cd /tmp/gentoo/usr/local/portage/ros-melodic/gscam &&\
#     wget  https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-melodic/gscam/Manifest&&\
#     mkdir files && cd files &&\
#     wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-melodic/gscam/files/0001-Prefer-Gstreamer-1.0-over-0.10.patch &&\
#     wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-melodic/gscam/files/Add-CMAKE-flag-to-compile-with-Gstreamer-version-1.x.patch &&\
#     cd .. && wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-melodic/gscam/gscam-1.0.1.ebuild &&\
#     ebuild gscam-1.0.1.ebuild manifest
RUN emerge ros-melodic/gscam

# Install in our locally known path pynaoqi (to avoid sourcing /opt/aldebaran/lib/python2.7...)
RUN wget https://github.com/awesomebytes/pepper_os/releases/download/pynaoqi-python2.7-2.5.5.5-linux32/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz &&\
    mkdir -p /home/nao/.local &&\
    cd /home/nao/.local &&\
    tar xvf /home/nao/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz &&\
    rm /home/nao/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz

# RUN cd /tmp/gentoo/usr/local/portage/ros-melodic/naoqi_libqicore &&\
#     rm Manifest && \
#     ebuild naoqi*.ebuild manifest

# TODO: this errors... shouldn't be too bad
# RUN emerge ros-melodic/pepper_meshes

RUN emerge dev-libs/libusb

RUN pip install --user dill cloudpickle uptime

# Apparently not available for melodic. If needed, just use from source
# RUN emerge ros-melodic/humanoid_nav_msgs
RUN emerge ros-melodic/rgbd_launch

# Fix all python shebangs
RUN cd ~/.local/bin &&\
    find ./ -type f -exec sed -i -e 's/\#\!\/usr\/bin\/python2.7/\#\!\/tmp\/gentoo\/usr\/bin\/python2.7/g' {} \;


# # Fix system stuff to not pull from .local python libs 
RUN echo -e "import sys\n\
if sys.executable.startswith('/usr/bin/python'):\n\
    sys.path = [p for p in sys.path if not p.startswith('/home/nao/.local')]" >> /home/nao/.local/lib/python2.7/site-packages/sitecustomize.py

# Enable pulseaudio if anyone manually executes startprefix
# Adding to the line 'RETAIN="HOME=$HOME TERM=$TERM USER=$USER SHELL=$SHELL"'
RUN sed 's/SHELL=$SHELL/SHELL=$SHELL XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR/g' /tmp/gentoo/startprefix_original

# Takes care of initializing the shell correctly
COPY --chown=nao:nao config/.bash_profile /home/nao/.bash_profile

# Takes care of booting roscore on boot
COPY --chown=nao:nao scripts/roscore_boot_manager.py /home/nao/.local/bin
COPY --chown=nao:nao scripts/run_roscore.sh /home/nao/.local/bin

# Run roscore on boot, executed by the robot on boot
RUN echo "/home/nao/.local/bin/roscore_boot_manager.py" >> /home/nao/naoqi/preferences/autoload.ini

# Fix new path on pynaoqi
RUN sed -i 's@/home/nao/pynaoqi-python2.7-2.5.5.5-linux32/lib/libqipython.so@/home/nao/.local/pynaoqi-python2.7-2.5.5.5-linux32/lib/libqipython.so@g' /home/nao/.local/pynaoqi-python2.7-2.5.5.5-linux32/lib/python2.7/site-packages/qi/__init__.py

RUN df -h
# TODO: https://github.com/uts-magic-lab/command_executer

ENTRYPOINT ["/tmp/gentoo/startprefix"]
