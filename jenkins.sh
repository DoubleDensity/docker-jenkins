#! /bin/bash

set -e

# Copy files from /usr/share/jenkins/ref into $JENKINS_HOME
# So the initial JENKINS-HOME is set with expected content.
# Don't override, as this is just a reference setup, and use from UI
# can then change this, upgrade plugins, etc.
copy_reference_file() {
	f="${1%/}"
	b="${f%.override}"
	echo "$f" >> "$COPY_REFERENCE_FILE_LOG"
	rel="${b:23}"
	dir=$(dirname "${b}")
	echo " $f -> $rel" >> "$COPY_REFERENCE_FILE_LOG"
	if [[ ! -e $JENKINS_HOME/${rel} || $f = *.override ]]
	then
		echo "copy $rel to JENKINS_HOME" >> "$COPY_REFERENCE_FILE_LOG"
		mkdir -p "$JENKINS_HOME/${dir:23}"
		cp -r "${f}" "$JENKINS_HOME/${rel}";
		# pin plugins on initial copy
		[[ ${rel} == plugins/*.jpi ]] && touch "$JENKINS_HOME/${rel}.pinned"
	fi;
}

# Start rpcbind for NFSv3 mounts
sudo service rpcbind start

# If NFS parameters are passed in then try to mount the target
if [ -n "${NFS_EXPORT+set}" ] && [ -n "${NFS_MOUNT+set}" ]; then
    if [ -e ${NFS_MOUNT} ]; then
        echo "Attempting to mount ${NFS_EXPORT} to ${NFS_MOUNT}"
        sudo mount -t nfs $NFS_EXPORT $NFS_MOUNT
    else
        echo "Creating ${NFS_MOUNT}"
        sudo mkdir -p $NFS_MOUNT
        echo "Attempting to mount ${NFS_EXPORT} to ${NFS_MOUNT}"
        sudo mount -t nfs $NFS_EXPORT $NFS_MOUNT
    fi
    
    : ${JENKINS_HOME:=${NFS_MOUNT}}
  
else
    : ${JENKINS_HOME:="/var/jenkins_home"}
fi

if [ -e ${JENKINS_HOME}/dockercfg ]; then
    echo "dockercfg detected on NFS mount, installing to /root"
    cp -v ${JENKINS_HOME}/dockercfg /root/.dockercfg
fi

export -f copy_reference_file
touch "${COPY_REFERENCE_FILE_LOG}" || (echo "Can not write to ${COPY_REFERENCE_FILE_LOG}. Wrong volume permissions?" && exit 1)
echo "--- Copying files at $(date)" >> "$COPY_REFERENCE_FILE_LOG"
find /usr/share/jenkins/ref/ -type f -exec bash -c "copy_reference_file '{}'" \;

# if `docker run` first argument start with `--` the user is passing jenkins launcher arguments
if [[ $# -lt 1 ]] || [[ "$1" == "--"* ]]; then
  eval "exec java $JAVA_OPTS -jar /usr/share/jenkins/jenkins.war $JENKINS_OPTS \"\$@\""
fi

# As argument is not jenkins, assume user want to run his own process, for sample a `bash` shell to explore this image
exec "$@"
