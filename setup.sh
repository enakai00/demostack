#!/bin/sh

####
intnic="eth1"
extnic="eth2"
public="10.0.1.0/24"
gateway="10.0.1.254"
pool=("10.0.1.100" "10.0.1.199")
nameserver="8.8.8.8"
private=("192.168.101.0/24" "192.168.102.0/24")
####

function controller {
    if ! md5sum --check --status ./images/Fedora18-cloud-init.qcow2.md5; then
        for s in $( ls ./images/x* ); do
            cat $s >> ./images/Fedora18-cloud-init.qcow2
        done
    fi

    export FACTER_PWD=$PWD
    puppet apply \
        --modulepath=./modules \
        --execute \
        "class {'setup::prereboot': \
            nodetype => 'controller', intnic => ${intnic}, extnic => ${extnic}}"
    return $?
}

function compute {
    export FACTER_PWD=$PWD
    puppet apply \
        --modulepath=./modules \
        --execute \
        "class {'setup::prereboot': \
            nodetype => 'compute', intnic => ${intnic}, extnic => 'none'}"
    return $?
}

function configproject {
    . /root/keystonerc_admin

    #
    # create project and users
    #
    keystone user-get demo_admin && keystone user-delete demo_admin
    keystone user-get demo_user && keystone user-delete demo_user
    keystone tenant-get demo && keystone tenant-delete demo

    keystone tenant-create --name demo
    keystone user-create --name demo_admin --pass passw0rd
    keystone user-create --name demo_user --pass passw0rd
    keystone user-role-add --user demo_admin --role admin --tenant demo
    keystone user-role-add --user demo_user --role Member --tenant demo

    #
    # initialize quantum db
    #
    quantum_services=$(systemctl list-unit-files --type=service \
        | grep -E 'quantum\S+\s+enabled' | cut -d" " -f1)

    for s in ${quantum_services}; do systemctl stop $s; done
    mysqladmin -f drop ovs_quantum
    mysqladmin create ovs_quantum
    quantum-netns-cleanup
    for s in $quantum_services; do systemctl start $s; done
    sleep 5

    #
    # create external network
    #
    tenant=$(keystone tenant-list | awk '/ services / {print $2}')
    quantum net-create \
        --tenant-id $tenant ext-network --shared \
        --provider:network_type flat \
        --provider:physical_network physnet1 \
        --router:external=True
    quantum subnet-create \
        --tenant-id $tenant --gateway ${gateway} --disable-dhcp \
        --allocation-pool start=${pool[0]},end=${pool[1]} \
        ext-network ${public}

    #
    # create router
    #
    tenant=$(keystone tenant-list|awk '/ demo / {print $2}')
    quantum router-create --tenant-id $tenant demo_router
    quantum router-gateway-set demo_router ext-network

    #
    # create private networks
    #
    for (( i = 0; i < ${#private[@]}; ++i )); do
        name=$(printf "private%02d" $(( i + 1 )))
        vlanid=$(printf "1%02d" $(( i + 1 )))
        subnet=${private[i]}
        quantum net-create \
            --tenant-id $tenant ${name} \
            --provider:network_type vlan \
            --provider:physical_network physnet2 \
            --provider:segmentation_id ${vlanid}
        quantum subnet-create \
            --tenant-id $tenant --name ${name}-subnet \
            --dns-nameserver ${nameserver} ${name} ${subnet}
        quantum router-interface-add demo_router ${name}-subnet
    done
}

function main {
    cmd=$(basename $0)
    path=${0%$cmd}
    cd $path
    magic=$(cat magic 2>/dev/null)
    if [[ $magic != "321d21fd-e813-4514-86ec-e3f2bb6856e4" ]]; then
        echo "Current directory should be the same as setup.sh."
        exit
    fi

    case $1 in
      "configproject")
        configproject
        echo "Done."
        ;;

      "controller")
        controller
        rc=$?
        if [[ $rc -eq 0 ]]; then
            echo "Done. Now you need to reboot the server."
        else
            echo "Failed."
        fi
        ;;

      "compute")
        compute
        rc=$?
        if [[ $rc -eq 0 ]]; then
            echo "Done. Now you need to reboot the server."
        else
            echo "Failed."
        fi
        ;;

      *)
        echo "Usage: $cmd controller|compute|configproject"
        ;;
    esac
}

##
main "$@"

