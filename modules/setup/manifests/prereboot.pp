class setup::prereboot ( $extnic = 'eth0') {
  include setup::selinux
  include setup::iptables
  include setup::bridgemodule
  include setup::libvirtnet
  include setup::roothelper_patch
  include setup::prepimage
  class {'setup::addport': extnic => $extnic } 

  package { 'vim-enhanced':
    ensure => 'installed',
  }
}

class setup::selinux {
  selinux::config { 'permissive':
    ensure => 'permissive',
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

class setup::bridgemodule {
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
    value => '1'
  }
  sysctl::value { 'net.bridge.bridge-nf-call-iptables':
    value => '1'
  }
  sysctl::value { 'net.bridge.bridge-nf-call-arptables':
    value => '1',
  }
}

class setup::libvirtnet {
  exec { 'virsh net-destroy default; virsh net-autostart default --disable':
    path => '/usr/bin',
    onlyif => 'virsh net-info default',
  }
}

class setup::addport ( $extnic ) {
  exec { "ovs-vsctl add-port br-ex ${extnic}":
    path => '/usr/bin',
    unless => "ovs-vsctl list-ports br-ex | grep ${extnic}",
  }

  exec { 'openstack-config --set /etc/quantum/quantum.conf DEFAULT ovs_use_veth True':
    path => '/usr/bin',
  }
}

class setup::roothelper_patch {
  define applypatch {
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

  applypatch { $files: }
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
