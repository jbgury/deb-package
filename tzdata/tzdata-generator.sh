#!/bin/bash
# Script to generate deb for tzdata and tzdata-java
# from the Olson public versions.


usage()
{
cat << EOF
usage: $0 options

 -f tzdata file to use.
 -v version (check version on the http://www.iana.org/time-zones )


    This script allows to generate tzdata and tzdata-java deb from the source
    Be sure that the dependencies of this packages are installed with :
        # apt-get build-dep tzdata
    Package source should be activated into /etc/sources.list
 
 
EOF
}

FILE_TZDATA=""
VERSION=""
while getopts ":f:v:h" opt; do
  case $opt in
    f)
      FILE_TZDATA=$OPTARG
      ;;
    v)
      VERSION=$OPTARG
      ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

[ ! -z ${FILE_TZDATA} ] && [ ! -e ${FILE_TZDATA} ] && echo "Fichier : $FILE_TZDATA non trouvé !" && usage && exit 1;
[ ! -z ${FILE_TZDATA} ] && [ ! -z ${VERSION} ] && echo "La version doit être précisée avec le fichier." && usage && exit 1;

CURRENT_DIR=$(pwd)
WORKING_DIR=build
DEB_SRC=${WORKING_DIR}/deb_source
DEBS=${WORKING_DIR}/debs

OLSON_DATA_SRC=${WORKING_DIR}/olson_tzdata
URL="hftp://ftp.iana.org"
DIR=tz
FILE=tzdata-latest.tar.gz

SRC_DIR=""
NAME="tzdata"
STRING_VERSION=""

# download source of the package
# and download data source of timezones
prepare_source()
{
	# create work directory 
	[ -e "${WORKING_DIR}" ] && rm -rf ${WORKING_DIR};
	mkdir -p ${DEB_SRC}
	mkdir -p ${DEBS}
	mkdir -p ${OLSON_DATA_SRC}
	# Get the source of the package.
	cd ${DEB_SRC}
	apt-get source tzdata
	[ "$?" -ne 0 ] && echo "An error occurs when downloading source of tzdata on this platform. Check if source packages are in the /etc/sources.list." && exit 1;
	
	# retrieve the olson data timezone.
	cd ${CURRENT_DIR}; 
	if [ -z "${FILE_TZDATA}" ]; then
		# recherche la cible du lien symbolique sur le serveur ftp de ${FILE}
		myfile=$(lftp "${URL}" -e "cd ${DIR}; rels | grep ${FILE}; quit")
		# ne garde que le nom du fichier, pas de chemin
		myfile="${myfile##*releases/}"
		[ -z "${myfile}" ] && echo "Impossible d'identifier la dernière releases sur ${URL}" && exit 1;
		# Télécharge le fichier dans les sources timezone data
		lftp "${URL}" -e "lcd ${OLSON_DATA_SRC}; cd ${DIR}; get ${FILE}; quit"
		[ "$?" -ne 0 ] && echo "An error occurs when download source of olson data on : ${URL}/${DIR}/${FILE}" && exit 1;
		# renomme le fichier correctement avec la version
		cd ${OLSON_DATA_SRC}; mv ${FILE} ${myfile};
		FILE=${myfile}
		# identifie le numéro de version.
		only_file="${myfile%%.tar.gz}"
		VERSION="${only_file##${NAME}}"
		cd ${CURRENT_DIR}
	else 
		cp ${FILE_TZDATA} ${OLSON_DATA_SRC}/${FILE};
	fi
	
	# decompress the data.
	cd ${OLSON_DATA_SRC};
	tar -xzf ${FILE};
	rm ${FILE};
	cd ${CURRENT_DIR}
	
	# Prepare the source of the package
	# Get the current version of the source package from the platform
	tzdata_src=$( find ${DEB_SRC} -name "${NAME}-*" -type d -print | xargs basename )
	version_tzdata_src=${tzdata_src##${NAME}-}
	if [ "${tzdata_src}" == "${NAME}-${VERSION}" ]; then
		echo ""
		echo "Source Version of the platform is up to date with the current olson data version."
		echo "Do you want to force the building of the package ? (y/N)"
		read item
		case $item in
			"y"|"Y" ) 
      			# should continue
	       			;;
       			* ) exit 0;;
		esac

	fi
	cp -rf ${DEB_SRC}/${tzdata_src} ${DEB_SRC}/${NAME}-${VERSION}
		
	# Copy the olson tzdata on the new src_package
	cp -rf ${OLSON_DATA_SRC}/* ${DEB_SRC}/${NAME}-${VERSION} 
	SRC_DIR=${DEB_SRC}/${NAME}-${VERSION}
}


# Patch the source changelog with the version to generate the version
patch_changelog()
{
	changelog_date=$(date -R)
	PATCH=/tmp/patch_changelog$$
	STRING_VERSION="${VERSION}-all"
	(
	echo "${NAME} (${STRING_VERSION}) stable; urgency=low";
	echo ""
	echo "  * Update tzdata to the upstream version ${VERSION}."
	echo "    - check the http://www.iana.org/time-zones to get more information."
	echo ""
	echo " -- MY NAME <yourname@email.com>  ${changelog_date}"
	echo ""
	) > ${PATCH}
	cat ${PATCH} ${DEB_SRC}/${tzdata_src}/debian/changelog > ${SRC_DIR}/debian/changelog
	rm ${PATCH}
	
}

# Patch the source of the deb to select only one directory where java should be found
patch_generator()
{
	cd ${SRC_DIR}
	# Apply patch on the file : debian/rules add the keyword firstword to avoid to expand both directories for JHOME
	sed debian/rules -i -e 's@\(JHOME.*\)\(\$(wildcard.*)\)@\1$(firstword \2)@g'
	cd ${CURRENT_DIR}
}

# Generate the deb files to be installed with dpkg -i
generate_debs()
{
	cd ${SRC_DIR}
	dpkg-buildpackage -rfakeroot -b
	[ "$?" -ne 0 ]&& echo "An error occurs when generating debs package. Please check the standard output" && exit 1
	cd ${CURRENT_DIR}
	mv ${DEB_SRC}/${NAME}*${STRING_VERSION}*.deb ${DEBS}/.
}

# extract the directory to generate the package tzdata and tzdata-java
extract_directory_deb()
{
	DEB_STRUCTURE="${DEB_SRC}/${NAME}-${VERSION}/debian"
	mv ${DEB_STRUCTURE}/${NAME} ${DEBS}/.
	mv ${DEB_STRUCTURE}/${NAME}-java ${DEBS}/.
}

usage
prepare_source
patch_changelog
patch_generator
generate_debs
extract_directory_deb

echo ""
echo "\o/  Good news, debs and directory structure are available into ${DEBS}. Version ${STRING_VERSION} generated."
echo ""
exit 0
