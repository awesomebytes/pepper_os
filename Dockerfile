FROM awesomebytes/pepper_2.5.5.5

USER nao
WORKDIR /home/nao

# Download and extract the Gentoo Prefix + ROS desktop image
RUN wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix_32b/releases/download/release%2F2019-01-11T02at56plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-x86_2019-01-11T02at56plus00at00.tar.gz.part-00 &\
    wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix_32b/releases/download/release%2F2019-01-11T02at56plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-x86_2019-01-11T02at56plus00at00.tar.gz.part-01 &\
    wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix_32b/releases/download/release%2F2019-01-11T02at56plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-x86_2019-01-11T02at56plus00at00.tar.gz.part-02 &\
    wait &&\
    cat gentoo_on_tmp* > gentoo_on_tmp.tar.gz &&\
    rm gentoo_on_tmp*.part* &&\
    tar xvf gentoo_on_tmp.tar.gz &&\
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

# update first
RUN emaint sync -a
# Prepare python
RUN emerge dev-python/pip
RUN pip install --user argparse

RUN echo ">=media-plugins/alsa-plugins-1.1.7 pulseaudio" >> $EPREFIX/etc/portage/package.use

RUN echo "# required by ros-kinetic/pcl_conversions-0.2.1::ros-overlay for navigation" >> $EPREFIX/etc/portage/package.accept_keywords &&\
    echo "=sci-libs/pcl-9999 **" >> $EPREFIX/etc/portage/package.accept_keywords

# Very ugly hack, need to fix this from whereve it came
# some packages are affected, others arent, weird
RUN cd /tmp/gentoo/opt &&\
    find ./ -type f -name *.pc -exec sed -i -e 's@/home/user/gentoo@/tmp/gentoo@g' {} \; &&\
    find ./ -type f -name *.cmake -exec sed -i -e 's@/home/user/gentoo@/tmp/gentoo@g' {} \;

# TODO: Need to fix https://bugs.gentoo.org/673464

# Navigation needs it becuase of ros-kinetic/move_slow_and_clear
# Giving error: 
RUN mkdir -p /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
    cd /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
    wget https://664126.bugs.gentoo.org/attachment.cgi?id=545428 -O gcc8.patch
RUN echo ">=sci-libs/pcl-1.9.1" >> /tmp/gentoo/etc/portage/package.mask
RUN echo "=sci-libs/pcl-1.8.1 **" >> /tmp/gentoo/etc/portage/package.accept_keywords
RUN emerge sci-libs/pcl

RUN emerge ros-kinetic/robot_state_publisher \
    ros-kinetic/geometry2 \
    ros-kinetic/ros_control
RUN emerge ros-kinetic/image_common \
    ros-kinetic/image_transport_plugins \
    ros-kinetic/diagnostics \
    ros-kinetic/octomap_msgs \
    ros-kinetic/tf2_geometry_msgs \
    ros-kinetic/ros_numpy \
    ros-kinetic/ddynamic_reconfigure_python

RUN emerge ros-kinetic/navigation
RUN emerge ros-kinetic/slam_gmapping
RUN emerge ros-kinetic/depthimage_to_laserscan
RUN emerge ros-kinetic/rosbridge_suite
RUN emerge ros-kinetic/cmake_modules \
    ros-kinetic/naoqi_bridge_msgs \
    ros-kinetic/perception_pcl \
    ros-kinetic/pcl_conversions \
    ros-kinetic/pcl_ros
RUN emerge media-libs/portaudio \
    net-libs/libnsl \
    dev-cpp/eigen

RUN emerge media-libs/opus

# To avoid: https://bugs.gentoo.org/673464
RUN echo ">=media-plugins/alsa-plugins-1.1.7-r1" >> /tmp/gentoo/etc/portage/package.mask
RUN echo ">=media-plugins/alsa-plugins-1.1.6 pulseaudio" >> /tmp/gentoo/etc/portage/package.use
RUN emerge media-sound/pulseaudio

# To avoid https://bugs.gentoo.org/676022
RUN echo ">=dev-java/icedtea-bin-3.10.0" >> /tmp/gentoo/etc/portage/package.mask

RUN emerge ros-kinetic/pepper_meshes

RUN emerge ros-kinetic/move_base_flex

# #     ros-kinetic/naoqi_libqicore \
# #     ros-kinetic/naoqi_libqi \
# # need the patches I made in ros_pepperfix

# #     ros-kinetic/web_video_server \
# # CODEC_FLAG_GLOBAL_HEADER -> AV_CODEC_FLAG_GLOBAL_HEADER

RUN pip install --user dlib
RUN pip install --user pysqlite
RUN pip install --user ipython
RUN pip install --user --upgrade numpy
RUN pip install --user scipy
RUN pip install --user pytz
RUN pip install --user wstool

RUN pip install --user Theano
RUN pip install --user keras
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

RUN pip install --user pyaudio

RUN pip install --user SpeechRecognition
RUN pip install --user nltk
RUN pip install --user pydub

RUN pip install --user ipython
RUN pip install --user jupyter

RUN pip install --user https://github.com/awesomebytes/pepper_os/releases/download/upload_tensorflow-1.6.0/tensorflow-1.6.0-cp27-cp27mu-linux_i686.whl

RUN pip install --user xxhash

RUN pip install --user catkin_tools

RUN emerge ros-kinetic/eband_local_planner
RUN cd /tmp/gentoo/usr/local/portage/ros-kinetic/libg2o &&\
    rm * &&\
    wget https://raw.githubusercontent.com/ros/ros-overlay/b76f702b1acfa384f0c43679a1fe67ab4c1f99fe/ros-kinetic/libg2o/libg2o-2016.4.24.ebuild &&\
    wget https://raw.githubusercontent.com/ros/ros-overlay/b76f702b1acfa384f0c43679a1fe67ab4c1f99fe/ros-kinetic/libg2o/metadata.xml &&\
    ebuild libg2o-2016.4.24.ebuild manifest
# # # undocumented dependency of teb_local_planner
# RUN emerge sci-libs/suitesparse
RUN cd /tmp/gentoo/etc/portage/patches/ros-kinetic &&\
    mkdir -p libg2o-2016.4.24 &&\
    cd libg2o-2016.4.24 &&\
    wget https://gist.githubusercontent.com/awesomebytes/97aad67cbc86deb93a76ace964241848/raw/bc83232c2ff5df872db0d3d46d49aca1a78ecbc7/001-Debug-cholmod.patch &&\
    wget https://gist.githubusercontent.com/awesomebytes/79bafc394be8389d6430393edf77be47/raw/faae7ba38692d05c841b0aa3495e1618a3a70ca0/002-Hardcode-BLAS.patch
RUN emerge sci-libs/cholmod
RUN emerge ros-kinetic/libg2o
RUN cd /tmp/gentoo/etc/portage/patches/ros-kinetic &&\
    mkdir -p teb_local_planner &&\
    cd teb_local_planner &&\
    wget https://gist.githubusercontent.com/awesomebytes/0e84ce3539cdbe6d8013a75f17de34a1/raw/c72c8d4f7d307e553629f18dab1c11d184e5295d/0001-Adapt-for-Gentoo-Prefix-on-tmp-gentoo.patch
RUN emerge ros-kinetic/teb_local_planner
RUN emerge ros-kinetic/dwa_local_planner
# Workaround
RUN cd /tmp/gentoo/usr/local/portage/ros-kinetic/sbpl_lattice_planner &&\
    rm Manifest && \
    ebuild sbpl*.ebuild manifest
RUN emerge ros-kinetic/sbpl_lattice_planner

RUN EXTRA_ECONF="--enable-pulse" emerge media-libs/gst-plugins-good
RUN emerge media-plugins/gst-plugins-opus \
    media-plugins/gst-plugins-v4l2 \
    media-plugins/gst-plugins-jpeg \
    media-plugins/gst-plugins-libpng \
    media-plugins/gst-plugins-lame
RUN emerge media-plugins/gst-plugins-x264 media-plugins/gst-plugins-x265

RUN cd /tmp/gentoo/usr/local/portage/ros-kinetic/gscam &&\
    wget  https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-kinetic/gscam/Manifest&&\
    mkdir files && cd files &&\
    wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-kinetic/gscam/files/0001-Prefer-Gstreamer-1.0-over-0.10.patch &&\
    wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-kinetic/gscam/files/Add-CMAKE-flag-to-compile-with-Gstreamer-version-1.x.patch &&\
    cd .. && wget https://raw.githubusercontent.com/ros/ros-overlay/80a3d06744df220fadb34b638d94d4336af2b720/ros-kinetic/gscam/gscam-1.0.1.ebuild &&\
    ebuild gscam-1.0.1.ebuild manifest
RUN emerge ros-kinetic/gscam

# Install in our locally known path pynaoqi (to avoid sourcing /opt/aldebaran/lib/python2.7...)
RUN wget https://github.com/awesomebytes/pepper_os/releases/download/pynaoqi-python2.7-2.5.5.5-linux32/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz &&\
    mkdir -p /home/nao/.local &&\
    cd /home/nao/.local &&\
    tar xvf /home/nao/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz &&\
    rm /home/nao/pynaoqi-python2.7-2.5.5.5-linux32.tar.gz
RUN ls

RUN cd /tmp && git clone https://github.com/awesomebytes/pepper_os &&\
    cp -r pepper_os/patches/* /tmp/gentoo/etc/portage/patches/ros-kinetic &&\
    rm -r pepper_os

RUN cd /tmp/gentoo/usr/local/portage/ros-kinetic/naoqi_libqicore &&\
    rm Manifest && \
    ebuild naoqi*.ebuild manifest

RUN emerge ros-kinetic/naoqi_libqi ros-kinetic/naoqi_libqicore

RUN emerge dev-libs/libusb

# Make ros_ws with
# naoqi_driver
# openni2_camera
# openni2_launch
# pal_msgs
# pepper_openni


RUN pip install --user dill
RUN pip install --user cloudpickle
RUN pip install --user uptime

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
COPY --chown=nao:nao roscore_boot_manager.py /home/nao/.local/bin
COPY --chown=nao:nao run_roscore.sh /home/nao/.local/bin

# Run roscore on boot, executed by the robot on boot
RUN echo "/home/nao/.local/bin/roscore_boot_manager.py" >> /home/nao/naoqi/preferences/autoload.ini

# TODO: https://github.com/uts-magic-lab/command_executer

ENTRYPOINT ["/tmp/gentoo/startprefix"]
