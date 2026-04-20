Vagrant.configure("2") do |config|

  # --- debian (naberius + vassago) ---

  config.vm.define "debian" do |debian|
    debian.vm.box      = "debian/bookworm64"
    debian.vm.hostname = "debian"

    debian.vm.network "private_network", ip: "192.168.56.20"

    debian.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus   = 1
    end

    debian.vm.provision "shell", path: "provision/debian.sh"
  end

  # --- kali (attacker) ---

  config.vm.define "kali" do |kali|
    kali.vm.box      = "kalilinux/rolling"
    kali.vm.hostname = "kali"

    kali.vm.network "private_network", ip: "192.168.56.10"

    kali.vm.provider "virtualbox" do |vb|
      # kali is heavier — GUI tools + attack frameworks pre-installed
      vb.memory = 2048
      vb.cpus   = 2
    end

    kali.vm.provision "shell", path: "provision/kali.sh"
  end

end