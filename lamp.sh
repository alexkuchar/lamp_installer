#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31mPlease run the script as root.\e[0m"
  exit 1
fi

DATA_DIR="/home/alxzr.cloud/lamp"
DATA_FILE="$DATA_DIR/data.txt"
LOG_FILE="$DATA_DIR/retry_logs.log"
mkdir -p $DATA_DIR
touch $DATA_FILE $LOG_FILE

retry_apt() {
  local max_attempts=5
  local attempt=1
  local log_file="/home/alxzr.cloud/lamp/retry_logs.log"

  while true; do
    apt-get "$@" -qq -o=Dpkg::Use-Pty=0 &> "$log_file"
    if [ $? -eq 0 ]; then
      break
    elif [ $attempt -lt $max_attempts ]; then
      attempt=$((attempt + 1))
      sleep 5
    else
      echo -e "\e[1;31m    Max attempts reached. Exiting...\e[0m"
      exit 1
    fi
  done
}

install_lamp_stack() {
  clear
  required_packages=("ca-certificates" "apt-transport-https" "lsb-release" "gnupg" "curl" "nano" "unzip")
  missing_packages=()

  for package in "${required_packages[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$package"; then
      missing_packages+=("$package")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    echo -e "\e[1;33m    The following required packages are missing: ${missing_packages[*]}\e[0m"
    read -p "            Do you want to install them now? (y/n): " install_packages
    if [ "$install_packages" == "y" ]; then
      retry_apt update
      retry_apt install -y "${missing_packages[@]}"
      clear
    else
      echo -e "\e[1;31m    Aborted. Please install the required packages and run the script again.\e[0m"
      exit 1
    fi
  fi

  export LC_ALL=C

  LOGO=$(cat << "EOF"
   _____  .____     ____  _______________________ 
  /  _  \ |    |    \   \/  /\____    /\______   \
 /  /_\  \|    |     \     /   /     /  |       _/
/    |    \    |___  /     \  /     /_  |    |   \
\____|__  /_______ \/___/\  \/_______ \ |____|_  /
        \/        \/      \_/        \/        \/ 
EOF
)

  ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)
  USER_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)
  USERNAME="lamp_user_$(head /dev/urandom | tr -dc A-Za-z | head -c 8)"
  server_ip=$(hostname -I | cut -d' ' -f1)
  echo "$LOGO" > "$DATA_FILE"
  echo -e "\nRoot Password: $ROOT_PASSWORD" >> "$DATA_FILE"
  echo -e "User Password: $USER_PASSWORD" >> "$DATA_FILE"
  echo -e "Username: $USERNAME" >> "$DATA_FILE"

  step() {
    echo -e "\n\e[1;34m$1\e[0m"
  }

  substep() {
    echo -e "\e[1;36m  $1\e[0m"
  }

  complete() {
    echo -e "\e[1;32m    ✔ Completed\e[0m"
  }


  echo -e "\n$LOGO"
  step "\n\nInitializing LAMP Stack installation..."

  step "Installing required packages..."
  substep "Installing ca-certificates, apt-transport-https, lsb-release, gnupg, curl, nano, unzip"
  retry_apt update
  retry_apt install ca-certificates apt-transport-https lsb-release gnupg curl nano unzip -y
  complete

  if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [ "$ID" == "debian" ]; then
      step "Detected Debian-based system. Adding PHP repository for Debian."
      substep "Adding GPG key and updating sources.list.d"
      curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/php-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/php.list
    elif [ "$ID" == "ubuntu" ]; then
      step "Detected Ubuntu-based system. Adding PHP repository for Ubuntu."
      substep "Adding GPG key and updating sources.list.d"
      add-apt-repository ppa:ondrej/php
    else
      echo "This script is intended for Debian or Ubuntu-based systems only."
      exit 1
    fi
  else
    echo "Unable to determine the Linux distribution. Aborted."
    exit 1
  fi
  complete

  step "Installing Apache, PHP, and MySQL..."
  substep "Updating packages"
  retry_apt update
  substep "Installing Apache, PHP, and MySQL"
  retry_apt install apache2 php8.2 php8.2-common php8.2-cli php8.2-curl php8.2-gd php8.2-intl php8.2-mbstring php8.2-mysql php8.2-opcache php8.2-readline php8.2-xml php8.2-xsl php8.2-zip php8.2-bz2 libapache2-mod-php8.2 mariadb-server mariadb-client -y
  complete

  step "Configuring MySQL with automatic root password and no-remote-root..."
  substep "Setting up root user"
  echo "CREATE USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';" | /usr/bin/mysql -u root &> /dev/null
  echo "FLUSH PRIVILEGES;" | /usr/bin/mysql -u root &> /dev/null
  complete

  step "Securing MySQL installation..."
  echo "mariadb-server-10.4 mysql-server/root_password password $ROOT_PASSWORD" | debconf-set-selections
  debconf-set-selections <<< "mariadb-server-10.4 mysql-server/root_password_again password $ROOT_PASSWORD"
  retry_apt install -y mariadb-server &> /dev/null
  complete

  step "Creating user account..."
  substep "Creating user $USERNAME with password $USER_PASSWORD"
  echo "CREATE USER '$USERNAME'@'localhost' IDENTIFIED BY '$USER_PASSWORD';" | /usr/bin/mysql -u root -p"$ROOT_PASSWORD" &> /dev/null
  echo "GRANT ALL PRIVILEGES ON *.* TO '$USERNAME'@'localhost' WITH GRANT OPTION;" | /usr/bin/mysql -u root -p"$ROOT_PASSWORD" &> /dev/null
  echo "FLUSH PRIVILEGES;" | /usr/bin/mysql -u root -p"$ROOT_PASSWORD" &> /dev/null
  complete

  step "Installing phpMyAdmin..."
  substep "Downloading phpMyAdmin"
  cd /usr/share
  retry_apt install unzip  
  curl -fsSL https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -o phpmyadmin.zip -qq
  unzip -qq phpmyadmin.zip || true  
  rm phpmyadmin.zip
  mv phpMyAdmin-*-all-languages phpmyadmin
  chmod -R 0755 phpmyadmin
  complete

  step "Configuring phpMyAdmin Apache config..."
  substep "Creating phpmyadmin.conf"

  cat <<EOL > /etc/apache2/conf-available/phpmyadmin.conf
  # phpMyAdmin Apache configuration

  Alias /phpmyadmin /usr/share/phpmyadmin

  <Directory /usr/share/phpmyadmin>
      Options SymLinksIfOwnerMatch
      DirectoryIndex index.php
  </Directory>

  # Disallow web access to directories that don't need it
  <Directory /usr/share/phpmyadmin/templates>
      Require all denied
  </Directory>
  <Directory /usr/share/phpmyadmin/libraries>
      Require all denied
  </Directory>
  <Directory /usr/share/phpmyadmin/setup/lib>
      Require all denied
  </Directory>
EOL
  complete
  
  step "Adding custom landing page..."
  substep "Removing current landing page..."
  rm -rf /var/www/html/index.html > /dev/null
  substep "Adding new landing page..."
  touch /var/www/html/index.html > /dev/null
  SERVER_IP=$(hostname -I | cut -d' ' -f1)
	sed "s/\$SERVER_IP/$SERVER_IP/g" <<EOL > /var/www/html/index.html
	<!DOCTYPE html>
	<html lang="en">
	<head>
	    <meta charset="UTF-8">
	    <meta name="viewport" content="width=device-width, initial-scale=1.0">
	    <title>alxzr.cloud - LAMP Installation</title>
	    <script src="https://cdn.tailwindcss.com"></script>
	</head>
	<body class="bg-gray-950 text-gray-200/50">
	    <div class="h-screen w-screen flex flex-col items-center justify-center">
		<h1 class="text-3xl md:text-7xl font-black text-transparent bg-clip-text bg-gradient-to-br from-indigo-600 to-sky-300 uppercase tracking-tighter">alxzr.cloud</h1>
		<hr class="py-1 w-80 border border-white rounded-full shadow-2xl shadow-sky-300 outline-none bg-gradient-to-br from-indigo-600 to-sky-300 my-4" />
		<p class="text-base font-medium leading-normal leading-loose text-white my-4">Thanks for using alxzr's LAMP installation script.</p>
		<h2 class="text-base md:text-lg font-black text-transparent bg-clip-text bg-gradient-to-br from-indigo-600 to-sky-300 uppercase tracking-tighter mb-6">Links</h2>
		<ul class="flex flex-col gap-4 text-center text-sm">
		    <li>
		        Manage your database here: <a href="http://$SERVER_IP/phpmyadmin" class="text-transparent bg-clip-text bg-gradient-to-br from-indigo-600 to-sky-300 font-black tracking-tighter">http://$SERVER_IP/phpmyadmin</a>
		    </li>
		    <li>
		        Enjoy your new website here: <a href="http://$SERVER_IP" class="text-transparent bg-clip-text bg-gradient-to-br from-indigo-600 to-sky-300 font-black tracking-tighter">http://$SERVER_IP</a>
		    </li>
		    <li>
		        Read our tutorial on how to go on from here, here: <a href="https://alxzr.cloud/" class="text-transparent bg-clip-text bg-gradient-to-br from-indigo-600 to-sky-300 font-black tracking-tighter">https://alxzr.cloud/</a>
		    </li>
		</ul>
	    </div>
	    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js" integrity="sha384-C6RzsynM9kWDrMNeT87bh95OGNyZPhcTNXj1NW7RuBCsyN/o0jlpcV8Qyq46cDfL" crossorigin="anonymous"></script>
	    <script>
		// Replace \$SERVER_IP with the actual server's IPv4 address
		document.querySelectorAll('a').forEach(function(link) {
		    link.href = link.href.replace('\$SERVER_IP', location.hostname);
		});
	    </script>
	</body>
	</html>
EOL

  
  complete

  step "Restarting Apache to apply changes..."
  substep "Restarting Apache"
  a2enconf phpmyadmin > /dev/null
  service apache2 restart  
  complete

  echo -e "$LOGO"

  cat <<EOF
  LAMP Stack installation completed successfully!
  Visit our website » https://alxzr.cloud/
  Path to data.txt » $DATA_FILE
  Thanks for using alxzr.cloud's LAMP Script!
  
  You should now be able to access your Website.
  ➥ http://$server_ip/
  ➥ http://$server_ip/phpmyadmin/
EOF
}

uninstall_lamp_stack() {
  LOGO=$(cat << "EOF"
   _____  .____     ____  _______________________ 
  /  _  \ |    |    \   \/  /\____    /\______   \
 /  /_\  \|    |     \     /   /     /  |       _/
/    |    \    |___  /     \  /     /_  |    |   \
\____|__  /_______ \/___/\  \/_______ \ |____|_  /
        \/        \/      \_/        \/        \/ 
EOF
)
  step() {
    echo -e "\n\e[1;34m$1\e[0m"
  }

  substep() {
    echo -e "\e[1;36m  $1\e[0m"
  }

  complete() {
    echo -e "\e[1;32m    ✔ Completed\e[0m"
  }
  clear
  echo -e "\n$LOGO"
  step "Uninstalling LAMP Stack..."

  substep "Purging packages..."
  retry_apt purge -y ca-certificates apt-transport-https lsb-release gnupg \
    apache2 php8.2 php8.2-common php8.2-cli php8.2-curl php8.2-gd php8.2-intl php8.2-mbstring \
    php8.2-mysql php8.2-opcache php8.2-readline php8.2-xml php8.2-xsl php8.2-zip php8.2-bz2 \
    libapache2-mod-php8.2 mariadb-server mariadb-client phpmyadmin > /dev/null

  substep "Removing directories..."
  rm -rf /usr/share/phpmyadmin /etc/apache2/conf-available/phpmyadmin.conf /home/alxzr.cloud/lamp > /dev/null
  rm -rf /var/www > /dev/null

  substep "Removing files..."
  rm -f /home/alxzr.cloud/lamp/data.txt /home/alxzr.cloud/lamp/logs.txt > /dev/null
  substep "Removing project directory..."
  rm -r /home/alxzr.cloud > /dev/null

  cat <<EOF
  LAMP Stack uninstalled successfully.
  Visit our website » https://alxzr.cloud/

  Thanks for using alxzr.cloud's LAMP Script!
EOF
}

echo -e "Would you like to install or uninstall the LAMP Stack? (i/u)"
read -p "> " choice

if [ "$choice" == "i" ]; then
  install_lamp_stack
elif [ "$choice" == "u" ]; then
  uninstall_lamp_stack
else
  echo -e "\e[1;31mInvalid choice. Use 'i' for install or 'u' for uninstall.\e[0m"
  exit 1
fi

