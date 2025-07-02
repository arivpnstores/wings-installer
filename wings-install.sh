echo "#####################################################"
echo "# BPM's Wings Auto Installer                        #"
echo "#                                                   #"
echo "# https://github.com/User-92/wings-installer        #"
echo "#                                                   #"
echo "# Ths script has no affiliation with the            #"
echo "#  pterodactyl project                              #"
echo "#####################################################"

# TODO:
# 1. Add option to enable swap
# 2. Add support for more distros

if [[ $EUID -ne 0 ]]; then
	echo "ERROR: Invalid Permissions. This script needs to be run as root!" 1>&2
	exit 1
fi

# VARIABLES --------------------------------------------------------------------

GITHUB_BRANCH="master"

WINGS_REPO="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_"
GITHUB_INSTALLER="https://raw.githubusercontent.com/User-92/wings-installer/$GITHUB_BRANCH"
EMAIL_REGEX="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

# Let's Encrypt
CONFIGURE_CERTS=false
FQDN="$1"
EMAIL="arivpnstore@gmail.com"

###############################################
#            OS CHECK FUNCTIONS               #
###############################################

check_architecture() {
	ARCH=$(uname -m)
	if [ $ARCH != "x86_64" ] && [ $ARCH != "amd64" ] && [ $ARCH != "arm64" ]; then
		echo "ERROR: Unsupported Architecture!"
	fi
}

check_pterodactyl() {
	if [ -d "/etc/pterodactyl" ]; then
		echo "It seems you already have pterodactyl wings installed on your system!"
		echo "Would you like to continue with the install? (y/N)"
		read -r PROCEED_INSTALL
		if [[ ! $PROCEED_INSTALL =~ [Yy] ]]; then
			echo "Aborted!"
			exit 1
		fi
	fi
}

###############################################
#          INSTALLATION FUNCTIONS             #
###############################################

install_curl() {
	echo "Installing curl ..."
	apt-get -y install curl
}

install_docker() {
	echo "Installing Docker ..."
	DOCKER_INSTALLED=$(dpkg-query -W --showformat='${Status}\n' docker | grep "install ok installed")
	
	CONTINUE_INSTALL=true
	if [ ! "" = "$DOCKER_INSTALLED" ]; then
		echo "Docker is already installed!"
		echo "Continue installing docker? (y/N): "
		read -r CINSTALL
		if [[ ! CINSTALL =~ [Yy] ]]; then
			CONTINUE_INSTALL=false
		fi
	fi

	if [ $CONTINUE_INSTALL == true ]; then
        apt-get -y install \
            apt-transport-https \
            ca-certificates \
            gnupg2 \
            software-properties-common

        curl -sSL https://get.docker.com/ | CHANNEL=stable bash
        
        echo "Enabling Docker..."
        systemctl enable --now docker
		echo "Docker Installation Finished!"
	fi
}

install_wings() {
	echo "Installing Pterodactyl Wings ..."
	mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "$WINGS_REPO$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64")"
	chmod u+x /usr/local/bin/wings
	echo "Wings Installation Finished!"
}

install_certbot() {
	echo "Installing certbot ..."
	apt install -y certbot
	apt install -y python3-certbot-nginx
	echo "Certbot Installation Finished!"
}

install_wings_daemon() {
    echo "Installing wings daemon ..."
    curl -o /etc/systemd/system/wings.service $GITHUB_INSTALLER/files/wings.service
    systemctl daemon-reload
    echo "Daemon Installation Finished!"
}

install_all() {
	echo "! INSTALLATION STARTED !"
	apt update
	install_curl
	install_docker
	install_wings
	[ "$CONFIGURE_CERTS" == true ] && config_certs
}


##########################################
#        CONFIGURE FUNCTIONS             #
##########################################

config_certs() {
	FAILED=false
	install_certbot

	systemctl stop nginx || true
	certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$FQDN" || FAILED=true
	systemctl start nginx || true
	
	if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FALIED" == true ]; then
		echo "Certificate Creation Failed!"
	fi
}

enable_autorenew() {
    CRON_LINE='0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart nginx"'
    ( crontab -u $(whoami) -l; echo "$CRON_LINE" ) | crontab -u $(whoami) -
}

valid_email() {
  [[ $EMAIL =~ ${EMAIL_REGEX} ]]
}

main() {
	#check_pterodactyl
	check_architecture
		CONFIGURE_CERTS=true
    fi

	if [[ $CONFIGURE_CERTS == true ]]; then
		while [ -z "$FQDN" ]; do
			echo -n "Set the FQDN to use for Let's Encrypt (node.example.com): "
			read -r FQDN
			CONTINUE=true
			CONFIRM_CONTINUE="n"
			[ -z "$FQDN" ] && echo "FQDN is required!"
			[ -d "/etc/letsencrypt/live/$FQDN/" ] && echo "Certificate with FQDN already exists!" && CONTINUE=false
			
			[ $CONTINUE == false ] && FQDN=""
			[ $CONTINUE == false ] && echo -e -n "Continue with SSL? (y/N)"
			[ $CONTINUE == false ] && read -r CONFIRM_CONTINUE

			if [[ ! "$CONFIRM_CONTINUE" =~ [Yy] ]] && [ $CONTINUE == false ]; then
				CONFIGURE_CERTS=false
				FQDN="none"
			fi
		done
	fi
	
	EMAIL=""
	if [[ $CONFIGURE_CERTS == true ]]; then
		while ! valid_email "$EMAIL"; do
			echo -n "Enter email address for Let's Encrypt: "
			read -r EMAIL

			valid_email "$EMAIL" || echo "Invalid Email!"
		done
	fi


	# Install Wings
	install_all

    ENABLE_RENEW=false
	if [[ $CONFIGURE_CERTS == true ]]; then
        enable_autorenew
    fi

    DAEMON_RESPONSE=""
        MAKE_DAEMON=true
		install_wings_daemon
	fi

	echo ""
	echo "INSTALLATION COMPLETE!"
	echo "* Wings has been installed. To configure wings, create a node on"
	echo "* the pterodactyl dashboard, go to the configuration tab, and click"
	echo "* 'Generate Token' on the right sidebar. Copy the command shown"
	echo "* and paste it in the wings server terminal."
	echo "* Official Documentation:"
	echo "* 	 https://pterodactyl.io/wings/1.0/installing.html#configure"
	echo ""
	if [[ $MAKE_DAEMON == true ]]; then
        echo "+ To start the wings daemon, run the command: systemctl enable --now wings"
    else
        echo "+ To start wings, run the command: sudo wings --debug"
    fi
    echo ""
}

main
