# Helper functions that are used in multiple other functions

# get user input
prompt_confirm() {
	while true; do
		read -rs -n 1 -p "${1:-Continue?} [y/n]: " REPLY
		case $REPLY in
			[yY]) echo -e "\e[32m[Yes]\e[0m"; return 0 ;;
			[nN]) echo -e "\e[32m[No]\e[0m"; return 1 ;;
			*) echo -e "\e[31m[Invalid Input]\e[0m"
		esac
	done
}

# Displays green checkmark or red [failed] to indicate if a step successfully ran or failed
exit_response() {
	if [[ $? != 0 ]]; then
		echo -e " \e[31m[failed]\e[0m"
		return 1
	else
		echo -e " \e[32m\xE2\x9C\x94\e[0m"
		return 0
	fi
}

# insert item into array
# thanks to http://cfajohnson.com/shell/?2013-01-08_bash_array_manipulation
insert() {
	local arrayname=${1:?Arrayname required} val=$2 num=${3:-1}
	local array
	eval "array=( \"\${$arrayname[@]}\" )"
	[ $num -lt 0 ] && num=0 #? Should this be an error instead?
	array=( "${array[@]:0:num}" "$val" "${array[@]:num}" )
	eval "$arrayname=( \"\${array[@]}\" )"
}

# check if array contains element, only returning for exact matches
elementInArray () {
	local e match="$1"; shift
	for e; do
		[[ "$e" == "$match" ]] && return 0
	done
	return 1
}

# make sure the chosen domain is valid. Currently the regex is limited. Subdomains with less than 3 characters are considered invalid. Need to fix.
validate_fqdn() {
	# on macOS validation requires gnu grep (brew install grep)
	[[ `which ggrep` ]] && g=g
	local domain
	domain=$1
	unset fqdn_is_valid invalid_fqdn existing_domains
	for conf_file in $(ls "${CONF_DIR}"/nginx/conf.d);do
		existing_domains+=( ${conf_file%.conf*} )
	done
	validate_fqdn=$(echo $1 | ${g}grep -P "(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)")
	if elementInArray "${domain}" "${existing_domains[@]}" && [[ -z $reconfigure ]];then
		echo -e "\n\e[3m$domain is already in use\e[0m\n"
	elif [[ $validate_fqdn  ]];then
		fqdn_is_valid=1
	else
		echo -e "\n\e[3m$domain is not a valid domain\e[0m\n"
	fi
}

# remove services from relevant arrays in dockerbunker.env after they have been installed/destroyed/configured/started etc..
remove_from_WEB_SERVICES() {
	for key in "${!WEB_SERVICES[@]}";do
		if [[ "$key" =~ "${PROPER_NAME}" ]];then
			unset WEB_SERVICES["$key"]
		fi
	done
	sed -i '/WEB_SERVICES/d' "${ENV_DIR}/dockerbunker.env"
	declare -p WEB_SERVICES >> "${ENV_DIR}/dockerbunker.env"
}

remove_from_CONFIGURED_SERVICES() {
	CONFIGURED_SERVICES=("${CONFIGURED_SERVICES[@]/"${PROPER_NAME}"}");
	for key in "${!CONFIGURED_SERVICES[@]}";do
		if [[ "${CONFIGURED_SERVICES[$key]}" == "" ]];then
			unset CONFIGURED_SERVICES[$key]
			if [[ -z "${CONFIGURED_SERVICES[@]}" ]];then
				unset ${CONFIGURED_SERVICES[@]}
			fi
		fi
	sed -i '/CONFIGURED_SERVICES/d' "${ENV_DIR}/dockerbunker.env"
	declare -p CONFIGURED_SERVICES >> "${ENV_DIR}/dockerbunker.env"
	done
}

remove_from_STATIC_SITES() {
	STATIC_SITES=("${STATIC_SITES[@]/"${SERVICE_DOMAIN[0]}"}");
	for key in "${!STATIC_SITES[@]}";do
		if [[ "${STATIC_SITES[$key]}" == "" ]];then
			unset STATIC_SITES[$key]
			if [[ -z "${STATIC_SITES[@]}" ]];then
				unset ${STATIC_SITES[@]}
			fi
		fi
	sed -i '/STATIC_SITES/d' "${ENV_DIR}/dockerbunker.env"
	declare -p STATIC_SITES >> "${ENV_DIR}/dockerbunker.env"
	done
}

remove_from_INSTALLED_SERVICES() {
	INSTALLED_SERVICES=("${INSTALLED_SERVICES[@]/"${PROPER_NAME}"}");
	for key in "${!INSTALLED_SERVICES[@]}";do
		if [[ "${INSTALLED_SERVICES[$key]}" == "" ]];then
			unset INSTALLED_SERVICES[$key]
			if [[ -z "${INSTALLED_SERVICES[@]}" ]];then
				unset ${INSTALLED_SERVICES[@]}
			fi
		fi
	sed -i '/INSTALLED_SERVICES/d' "${ENV_DIR}/dockerbunker.env"
	declare -p INSTALLED_SERVICES >> "${ENV_DIR}/dockerbunker.env"
	done
}

remove_from_STOPPED_SERVICES() {
	STOPPED_SERVICES=("${STOPPED_SERVICES[@]/"${PROPER_NAME}"}");
	for key in "${!STOPPED_SERVICES[@]}";do
		if [[ "${STOPPED_SERVICES[$key]}" == "" ]];then
			unset STOPPED_SERVICES[$key]
			if [[ -z "${STOPPED_SERVICES[@]}" ]];then
				unset ${STOPPED_SERVICES[@]}
			fi
		fi
	done
	sed -i '/STOPPED_SERVICES/d' "${ENV_DIR}/dockerbunker.env"
	declare -p STOPPED_SERVICES >> "${ENV_DIR}/dockerbunker.env"
}

remove_from_CONTAINERS_IN_DOCKERBUNKER_NETWORK() {
	for container in ${add_to_network[@]};do
		CONTAINERS_IN_DOCKERBUNKER_NETWORK=("${CONTAINERS_IN_DOCKERBUNKER_NETWORK[@]/"$container"}");
		for key in "${!CONTAINERS_IN_DOCKERBUNKER_NETWORK[@]}";do
			if [[ "${CONTAINERS_IN_DOCKERBUNKER_NETWORK[$key]}" == "" ]];then
				unset CONTAINERS_IN_DOCKERBUNKER_NETWORK[$key]
				if [[ -z "${CONTAINERS_IN_DOCKERBUNKER_NETWORK[@]}" ]];then
					unset ${CONTAINERS_IN_DOCKERBUNKER_NETWORK[@]}
				fi
			fi
		done
		sed -i '/CONTAINERS_IN_DOCKERBUNKER_NETWORK/d' "${ENV_DIR}/dockerbunker.env"
		declare -p CONTAINERS_IN_DOCKERBUNKER_NETWORK >> "${ENV_DIR}/dockerbunker.env" 2>/dev/null
	done
}

collectAllImageNamesFromDockerComposeFile() {
	unset IMAGES
	for i in $(grep "image:" ${SERVICE_HOME}/docker-compose.yml | awk '{print $NF}');do IMAGES+=( \"$i\" );done
}

collectImageNamesAndCorrespondingSha256() {
	[[ $DOCKER_COMPOSE ]] && collectAllImageNamesFromDockerComposeFile
	for image in ${IMAGES[@]};do
		image=${image//\"}
		tag=${image#*:}
		image=${image%%:*}
		sha256=$(\
			docker images --no-trunc \
				| grep $image \
				| grep $tag \
				| awk '{for (i=1;i<=NF;i++){if ($i ~/^sha256/) {print $i}}}' \
				| awk -F":" '{print $NF}'\
			)
		declare -gA test IMAGES_AND_SHA256
		IMAGES_AND_SHA256[$image]+=$sha256
	done
}

say_done() {
	echo -e "\n\e[1mDone.\e[0m"
}

