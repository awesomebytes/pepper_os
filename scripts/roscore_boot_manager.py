#!/usr/bin/env python

import socket
import time
from platform import node as get_machine_name
from subprocess import check_output
from multiprocessing import Process, Queue
import sys
# To find uptime...
sys.path.append('/home/nao/.local/lib/python2.7/site-packages')
from uptime import uptime
import os

"""
Run roscore on different
network interfaces.

Author: Sammy Pfeiffer <Sammy.Pfeiffer@student.uts.edu.au>
"""

UPTIME_WAIT = 30.0


def check_server(address, queue, port=11311):
    # Create a TCP socket
    s = socket.socket()
    try:
        s.connect((address, port))
        # print("Port open at IP %s (on port %s)" % (address, port))
        queue.put((True, address, port))
    except socket.error as e:
        # print("Connection to %s on port %s failed: %s" % (address, port, e))
        queue.put((False, address, port))


def get_own_ip():
    return ((([ip for ip in socket.gethostbyname_ex(socket.gethostname())[2] if not ip.startswith("127.")] or [[(s.connect(("8.8.8.8", 53)), s.getsockname()[0], s.close()) for s in [socket.socket(socket.AF_INET, socket.SOCK_DGRAM)]][0][1]]) + ["no IP found"])[0])


def get_machine_network_ids():
    """
    Return machine name, and IPs of the machine.
    :return list:
    """
    addresses = []
    addresses.append(get_machine_name())
    ifconfig_str = check_output('ifconfig')

    for line in ifconfig_str.split('\n'):
        if line.startswith('          inet addr:'):
            for item in line.split():
                if item.startswith('addr:'):
                    addresses.append(item.replace('addr:', ''))
        elif line.startswith('        inet '):
            # in the robot ifconfig returns a different line
            addresses.append(line.split()[1])

    return addresses


def get_pepper_interface_ip(interface_name):
    print("Getting Pepper " + interface_name + " ip...")
    ifconfig_str = check_output(['ifconfig', interface_name])
    ip = ""
    for line in ifconfig_str.split('\n'):
        if line.startswith('        inet '):
            # in the robot ifconfig returns a different line
            ip = line.split()[1]
    if ip:
        print("Got ip: " + str(ip))
    else:
        print("No ip.")
    return ip


def get_pepper_name():
    return get_machine_name()


def scan_for_roscores(own_ip=None, timeout=3.0):
    """
    Scan for port 11311 open on a subnet.
    """
    if own_ip is None:
        own_ip = get_own_ip()
    if own_ip:
        ip_split = own_ip.split('.')
        subnet = ip_split[:-1]
        subnetstr = '.'.join(subnet)
        processes = []
        q = Queue()
        for i in range(1, 255):
            ip = subnetstr + '.' + str(i)
            p = Process(target=check_server, args=[ip, q])
            processes.append(p)
            p.start()
        # give a bit of time...
        time.sleep(timeout)

        found_ips = []
        for idx, p in enumerate(processes):
            if p.exitcode is None:
                # print("Terminating: " + str(idx))
                p.terminate()
            else:
                open_ip, address, port = q.get()
                if open_ip:
                    found_ips.append(address)

        for idx, p in enumerate(processes):
            # print("joining " + str(idx))
            p.join()

        print("Found ips: " + str(found_ips))
        return found_ips

    else:
        print("Could not get our own IP, can't scan our network.")
        return []


def wait_for_uptime(min_uptime_time):
    time_on = uptime()
    if time_on < min_uptime_time:
        print("The system has been on only for " + str(time_on) +
              "s, waiting for the system to be on for at least " +
              str(min_uptime_time))
        time.sleep(min_uptime_time - time_on)


def use_auto_network():
    """
    Run roscore trying first on wlan, then eth,
    finally localhost if nothing else.
    """
    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("Maybe waiting for uptime...")
    wait_for_uptime(UPTIME_WAIT)
    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("getting wlan0 ip...")
    wlan_ip = get_pepper_interface_ip('wlan0')
    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("getting eth0 ip...")
    eth_ip = get_pepper_interface_ip('eth0')
    ip = ''
    if wlan_ip:
        ip = wlan_ip
    elif eth_ip:
        ip = eth_ip
    run_roscore_on_network(ip)


def use_auto_eth_network():
    """
    Run roscore trying first on eth, then wlan,
    finally localhost if nothing else.
    """
    wait_for_uptime(UPTIME_WAIT)
    wlan_ip = get_pepper_interface_ip('wlan0')
    eth_ip = get_pepper_interface_ip('eth0')
    ip = ''
    if eth_ip:
        ip = eth_ip
    elif wlan_ip:
        ip = wlan_ip
    run_roscore_on_network(ip)


def use_wifi_network():
    """
    Run roscore trying first on wlan, then localhost.
    """
    wait_for_uptime(UPTIME_WAIT)
    ip = get_pepper_interface_ip('wlan0')
    run_roscore_on_network(ip)


def use_eth_network():
    """
    Run roscore trying first on eth, then localhost.
    """
    wait_for_uptime(UPTIME_WAIT)
    ip = get_pepper_interface_ip('eth0')
    run_roscore_on_network(ip)


def run_roscore_on_network(ip='localhost'):
    """
    Run roscore in the provided network ip. Defaults to localhost.
    """
    cmd = "/home/nao/.local/bin/run_roscore.sh " + ip
    print("Running: " + str(cmd))
    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("Executing: '" + cmd + "'\n")
        output = check_output(cmd.split())
        f.write("Got output:\n" + str(output) + '\n')
    # os.system(cmd)


def run_roscore_on_mode(mode='auto'):
    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("Running roscore on mode: " + str(mode) + "\n")
    if mode == 'auto' or mode == '':
        use_auto_network()
    elif mode == 'autoeth':
        use_auto_eth_network()
    elif mode == 'wlan':
        use_wifi_network()
    elif mode == 'eth':
        use_eth_network()
    elif mode == 'localhost':
        run_roscore_on_network('localhost')
    else:
        exit(-1)


if __name__ == '__main__':
    # For debug
    with open('/home/nao/.autoload_time', 'a') as f:
        log = "Uptime when autoload.ini was called: " + str(uptime()) + "\n"
        f.write(log)

    with open('/home/nao/.roscore_boot_manager.log', 'a') as f:
        f.write("roscore_boot_manager.py called with arguments:" +
                str(sys.argv) + "\n")

    if len(sys.argv) > 1:
        mode = sys.argv[1]
    else:
        mode = 'auto'
    # autoload.ini adds
    # '--pip 127.0.0.1 --pport 9559' to any Python file apparently
    if mode == '--pip':
        mode = 'auto'
    if mode == '-h':
        print("Usage:")
        print(sys.argv[0] + " [auto/autoeth/wlan/eth/localhost]\n")
        print("Run roscore (killing any running one) on one of the modes:")
        print("  auto: Try wlan, then eth, then localhost. It's the default.")
        print("  autoeth: Try eth, then wlan, then localhost")
        print("  wlan: Try wlan, then localhost")
        print("  eth: Try eth, then localhost")
        print("  localhost: Run on localhost")
        exit(1)
    run_roscore_on_mode(mode)
