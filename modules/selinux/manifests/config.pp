define selinux::config (
  $ensure = 'enforcing'
) {
  $config_enforcing ='# Configured with demostack
SELINUX=enforcing
SELINUXTYPE=targeted 
'
  $config_permissive ='# Configured with demostack
SELINUX=permissive
SELINUXTYPE=targeted 
'
  if $ensure == 'enforcing' {
    exec { 'setenforce 1':
      path => ['/usr/sbin'],
    }

    file { '/etc/selinux/config':
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $config_enforcing,
    }
  }
  elsif $ensure == 'permissive' {
    exec { 'setenforce 0':
      path => ['/usr/sbin'],
    }

    file { '/etc/selinux/config':
      owner => 'root',
      group => 'root',
      mode  => '0644',
      content => $config_permissive,
    }
  }
  else {
    fail "${ensure} for 'ensure' is not supported!"
  }
}
