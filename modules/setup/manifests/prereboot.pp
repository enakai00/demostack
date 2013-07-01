class setup::prereboot (
  $nodetype = 'controller',
  $extnic = 'eth1',
  $intnic = 'eth2'
) {
  if $nodetype == 'controller' {
    include setup::selinux
    include setup::iptables
    include setup::libvirtnet
    include setup::quickpatch1
    include setup::quickpatch2
    include setup::prepimage
    include setup::controller_setting

    class { 'setup::bridgemodule':
      bridge_nf_call => 1,
    }

    class {'setup::addport':
      intnic => $intnic,
      extnic => $extnic,
    } 

    package { 'vim-enhanced':
      ensure => 'installed',
    }
  }

  elsif $nodetype == 'compute' {
    include setup::selinux
    include setup::iptables
    include setup::libvirtnet
    include setup::quickpatch1

    class { 'setup::bridgemodule':
      bridge_nf_call => 0,
    }

    class {'setup::addport':
      intnic => $intnic,
      extnic => 'none',
    } 
  }
}

class setup::selinux {
  selinux::config { 'permissive':
    ensure => 'permissive',
  }
}

class setup::controller_setting {
  service { 'openstack-nova-compute':
    ensure => 'stopped',
    enable => 'false',
  }

  define restart_service {
    service { "${name}": 
      ensure    => 'running',
      enable    => 'true',
      subscribe => [Exec['set_vlan_range'], Exec['set_bridge_mappings']],
    }
  }

  $services = [
    'quantum-dhcp-agent',
    'quantum-l3-agent',
    'quantum-metadata-agent',
    'quantum-openvswitch-agent',
    'quantum-server',
  ]

  restart_service { $services: }

  exec { 'set_vlan_range':
    command => 'openstack-config --set /etc/quantum/plugin.ini OVS network_vlan_ranges physnet1,physnet2:100:199',
    path    => '/usr/bin',
  }

  exec { 'set_bridge_mappings':
    command => 'openstack-config --set /etc/quantum/plugin.ini OVS bridge_mappings physnet1:br-ex,physnet2:br-priv',
    path    => '/usr/bin',
  }
}

class setup::iptables {
  service { 'iptables':
    ensure  => 'running',
    enable  => 'true',
    require => Service['firewalld'],
  }

  service { 'firewalld':
    ensure => 'stopped',
    enable => 'false',
  }
}

class setup::bridgemodule ( $bridge_nf_call = '1' ) {
  $content = '#!/bin/sh
modprobe -b bridge >/dev/null 2>&1
exit 0
'
  file { '/etc/sysconfig/modules/openstack-quantum-linuxbridge.modules':
    owner   => 'root',
    group   => 'root',
    mode    => '0744',
    content => $content,
  }

  sysctl::value { 'net.bridge.bridge-nf-call-ip6tables':
    value => $bridge_nf_call
  }
  sysctl::value { 'net.bridge.bridge-nf-call-iptables':
    value => $bridge_nf_call
  }
  sysctl::value { 'net.bridge.bridge-nf-call-arptables':
    value => $bridge_nf_call
  }
}

class setup::libvirtnet {
  exec { 'virsh net-destroy default; virsh net-autostart default --disable':
    path => '/usr/bin',
    onlyif => 'virsh net-info default',
  }
}

class setup::addport ( $intnic, $extnic ) {
  exec { "ovs-vsctl add-port br-priv ${intnic}":
    path => '/usr/bin',
    unless => "ovs-vsctl list-ports br-priv | grep ${intnic}",
  }

  if $extnic != 'none' {
    exec { "ovs-vsctl add-port br-ex ${extnic}":
      path => '/usr/bin',
      unless => "ovs-vsctl list-ports br-ex | grep ${extnic}",
    }
  }

  exec { 'openstack-config --set /etc/quantum/quantum.conf DEFAULT ovs_use_veth True':
    path => '/usr/bin',
  }
}

class setup::quickpatch1 {
  #https://bugzilla.redhat.com/show_bug.cgi?id=972239
  define apply_root_helper_patch {
    exec { "sed -i.bak \"s/self\\.conf\\.root_helper/self\\.root_helper/\" ${name}":
      path   => '/bin',
      onlyif => "grep self.conf.root_helper ${name}",
    }
  }

  $files = [
    '/usr/lib/python2.*/site-packages/quantum/agent/linux/interface.py',
    '/usr/lib/python2.*/site-packages/quantum/agent/dhcp_agent.py',
    '/usr/lib/python2.*/site-packages/quantum/agent/l3_agent.py',
  ]

  apply_root_helper_patch { $files: }
}

class setup::quickpatch2 {
  # https://bugzilla.redhat.com/show_bug.cgi?id=977786
  package { 'qpid-cpp-server-ha':
    ensure => 'installed',
  }    

  service { 'qpidd':
    ensure  => 'running',
    enable  => 'true',
    require => Package['qpid-cpp-server-ha'],
  }

  exec { "sed -i.bak 's/cluster-mechanism/ha-mechanism/' /etc/qpidd.conf":
    path   => '/bin',
    onlyif => 'grep cluster-mechanism /etc/qpidd.conf',
    notify => Service['qpidd'],
  }
}

class setup::prepimage {
  file { '/var/www/html/images':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/var/www/html/images/Fedora18-cloud-init.qcow2':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => "${pwd}/images/Fedora18-cloud-init.qcow2",
    require => File['/var/www/html/images'],
  }
}

