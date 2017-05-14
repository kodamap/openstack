#!/bin/sh -e

export LANG=en_US.utf8

if [ $# -ne 4 ]; then
    echo "** Usage: $0 <object node1 ip> <object node2 ip> <device name1> <device name2>"
    exit 0
fi

object1=$1
object2=$2
device1=$3
device2=$4

# To create the ring
# Note :
# Perform these steps on the controller node.

create_account_ring () {

    echo
    echo "** create_account_ring started. **"
    echo

    # Change to the /etc/swift directory.
    cd /etc/swift

    # Create the base account.builder file:
    swift-ring-builder account.builder create 10 3 1

    # Add each storage node to the ring:
    swift-ring-builder account.builder add r1z1-${object1}:6002/${device1} 100
    swift-ring-builder account.builder add r1z2-${object1}:6002/${device2} 100
    swift-ring-builder account.builder add r1z3-${object2}:6002/${device1} 100
    swift-ring-builder account.builder add r1z4-${object2}:6002/${device2} 100

    # Verify the ring contents:
    echo
    echo "** swift-ring-builder account.builder **"
    echo

    swift-ring-builder account.builder

    # Rebalance the ring
    echo
    echo "** swift-ring-builder account.builder rebalance **"
    echo

    swift-ring-builder account.builder rebalance

    echo
    echo "** Done. **"
    echo

}

create_contrainer_ring () {

    echo
    echo "** create_contrainer_ring started. **"
    echo

    # Change to the /etc/swift directory.
    cd /etc/swift

    # Create the base contrainer.builder file:
    swift-ring-builder container.builder create 10 3 1

    # Add each storage node to the ring:
    swift-ring-builder container.builder add r1z1-${object1}:6001/${device1} 100
    swift-ring-builder container.builder add r1z2-${object1}:6001/${device2} 100
    swift-ring-builder container.builder add r1z3-${object2}:6001/${device1} 100
    swift-ring-builder container.builder add r1z4-${object2}:6001/${device2} 100

    # Verify the ring contents:
    echo
    echo "** swift-ring-builder container.builder **"
    echo

    swift-ring-builder container.builder

    # Rebalance the ring
    echo
    echo "** swift-ring-builder container.builder rebalance **"
    echo

    swift-ring-builder container.builder rebalance

    echo
    echo "** Done. **"
    echo

}

create_object_ring () {

    echo
    echo "** create_object_ring started. **"
    echo

    # Change to the /etc/swift directory.
    cd /etc/swift

    # Create the base object.builder file:
    swift-ring-builder object.builder create 10 3 1

    # Add each storage node to the ring:
    swift-ring-builder object.builder add r1z1-${object1}:6000/${device1} 100
    swift-ring-builder object.builder add r1z2-${object1}:6000/${device2} 100
    swift-ring-builder object.builder add r1z3-${object2}:6000/${device1} 100
    swift-ring-builder object.builder add r1z4-${object2}:6000/${device2} 100

    # Verify the ring contents:
    echo
    echo "** swift-ring-builder object.builder **"
    echo

    swift-ring-builder object.builder

    # Rebalance the ring
    echo
    echo "** swift-ring-builder object.builder rebalance **"
    echo

    swift-ring-builder object.builder rebalance

    echo
    echo "** Done. **"
    echo

}


distribute_ring_files () {

    echo
    echo "** distribute_ring_files started. **"
    echo

    # Distribute ring configuration files
    # Copy the account.ring.gz, container.ring.gz, and object.ring.gz files to
    # the /etc/swift directory on each storage node and any additional nodes running the proxy service.
    cd /etc/swift
    scp account.ring.gz container.ring.gz object.ring.gz root@${object1}:/etc/swift/
    scp account.ring.gz container.ring.gz object.ring.gz root@${object2}:/etc/swift/

    echo
    echo "** Done. **"
    echo
}

# main

create_account_ring
create_contrainer_ring
create_object_ring
distribute_ring_files
