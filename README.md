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