FROM awesomebytes/pepper_2.5.5.5

USER nao
WORKDIR /home/nao

# ENTRYPOINT ["/bin/bash"]

# Download and extract the Gentoo Prefix + ROS desktop image
RUN wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix/releases/download/release%2F2018-12-28T02at16plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-amd64_2018-12-28T02at16plus00at00.tar.gz.part-00 &\
    wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix/releases/download/release%2F2018-12-28T02at16plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-amd64_2018-12-28T02at16plus00at00.tar.gz.part-01 &\
    wget http://github.com/awesomebytes/ros_overlay_on_gentoo_prefix/releases/download/release%2F2018-12-28T02at16plus00at00/gentoo_on_tmp_with_ros-kinetic_desktop-amd64_2018-12-28T02at16plus00at00.tar.gz.part-02 &\
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

# Navigation needs it
RUN mkdir -p /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
    cd /tmp/gentoo/etc/portage/patches/sci-libs/pcl-1.8.1 && \
    wget https://664126.bugs.gentoo.org/attachment.cgi?id=545428 -O gcc8.patch
RUN echo ">=sci-libs/pcl-1.9.1" >> /tmp/gentoo/etc/portage/package.mask
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
# RUN emerge ros-kinetic/pepper_meshes
# dev-java/icedtea-web-1.6.2 failed

RUN emerge ros-kinetic/navigation
RUN emerge ros-kinetic/slam_gmapping
RUN emerge ros-kinetic/depthimage_to_laserscan
# workaround for rosbridge suite
RUN echo "dev-python/m2crypto-0.31.0" >> /tmp/gentoo/etc/portage/profile/package.provided
RUN pip install --user m2crypto
RUN emerge ros-kinetic/rosbridge_suite
RUN emerge ros-kinetic/cmake_modules \
    ros-kinetic/naoqi_bridge_msgs \
    ros-kinetic/perception_pcl \
    ros-kinetic/pcl_conversions \
    ros-kinetic/pcl_ros
RUN emerge media-libs/portaudio \
    net-libs/libnsl \
    dev-cpp/eigen

# media-sound/pulseaudio

# #     ros-kinetic/naoqi_libqicore \
# #     ros-kinetic/naoqi_libqi \
# # need the patches I made in ros_pepperfix
# #     ros-kinetic/move_base_flex
# # needs some dependency
# #     ros-kinetic/web_video_server \
# # CODEC_FLAG_GLOBAL_HEADER -> AV_CODEC_FLAG_GLOBAL_HEADER

# RUN pip install --user pysqlite
# RUN pip install --user ipython
# # Fix all python shebangs
# RUN cd ~/.local/bin &&\
#     find ./ -type f -exec sed -i -e 's/\#\!\/usr\/bin\/python2.7/\#\!\/tmp\/gentoo\/usr\/bin\/python2.7/g' {} \;

# RUN pip install --user --upgrade numpy
# RUN pip install --user scipy
# RUN pip install --user pytz
# RUN pip install --user wstool

# RUN pip install --user Theano
# RUN pip install --user keras

# # Tensorflow pending from our custom compiled one...
# # Which would be nice to automate too

# RUN pip install --user h5py
# RUN pip install --user opencv-python opencv-contrib-python

# RUN pip install --user pyaudio

# RUN pip install --user SpeechRecognition
# RUN pip install --user nltk
# RUN pip install --user pydub
# # TODO: binarize dlib, takes long to self compile
# RUN pip install --user dlib

# # Fix system stuff to not pull from .local python libs
# RUN echo "import sys\n\
# if sys.executable.startswith('/usr/bin/python'):\n\
#     sys.path = [p for p in sys.path if not p.startswith('/home/nao/.local')]" >> /home/nao/.local/lib/python2.7/site-packages/sitecustomize.py

# source /tmp/gentoo/opt/ros/kinetic/setup.bash
# export ROS_LANG_DISABLE=genlisp:geneus
# export CATKIN_PREFIX_PATH=/tmp/gentoo/opt/ros/kinetic

# TODO: add bash
# echo "
# # Check if the link exists in /tmp/gentoo
# # If it doesn't exist, create it
# if [ ! -L /tmp/gentoo ]; then
#   echo 'Softlink to this Gentoo Prefix in /tmp/gentoo does not exist, creating it...'
#   cd /tmp
#   ln -s /home/nao/gentoo gentoo
# fi

# # If not running interactively, don't do anything
# case $- in
#     *i*) ;;
#       *) return;;
# esac

# # This takes care of initializing the ROS Pepperfix environment
# if [[ $SHELL != /tmp/gentoo/bin/bash ]] ; then
#     exec /tmp/gentoo/startprefix
# fi
# # Source ROS Kinetic on Gentoo Prefix
# source /tmp/gentoo/opt/ros/kinetic/setup.bash
# " >> .bashrc



# etc etc
# ENTRYPOINT ["/bin/bash"]
ENTRYPOINT ["/tmp/gentoo/startprefix"]