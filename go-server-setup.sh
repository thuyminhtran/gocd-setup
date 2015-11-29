#!/bin/sh
# (C) 2015 Gunnar Andersson
# License: CC-BY-4.0 (https://creativecommons.org/licenses/by/4.0/)

version=15.2.0-2248

fail() { echo "Something went wrong - check script" ; echo $@ ; exit 1 ; }

type=
[ -e /etc/redhat-release ] && type=rpm
[ -e /etc/debian-release ] && type=deb
[ -x "$(which apt-get)" ] && type=deb
[ -x "$(which yum)" ] && type=rpm
[ -x "$(which dnf)" ] && type=rpm
[ -z "$type" ] && { fail "Can't figure out rpm/rpm - please check script" ; exit 1 ; }

server=go-server-${version}.noarch.${type}

serverurl=

# The download URL seems to require an actual web browser as agent
# or something?  The redirect to the file fails otherwise.
# We need the download so here's an agent string...
agent_str="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8)"

curl=$(which curl)
[ -x "$curl" ] || { echo "Can't find curl -- not installed?" ; exit 1 ; }

curl -C - -A "$agent_str" -L https://download.go.cd/gocd-$type/$server >$server || fail "download failed, (is curl installed?)"

case $type in
   rpm)
      sudo yum install -y java-1.7.0-openjdk
      sudo rpm -iv $server
      ;;
   deb)
      sudo apt-get install -y openjdk-7-jre
      sudo dpkg -i $server
      ;;
   *)
      fail
      ;;
esac

echo 'Creating "go" user'
sudo groupadd go
sudo useradd go -G go

echo "Fixing install/log directories to be accessible for go user"
sudo chown -R go:go /var/{log,run,lib}/go-server

sudo cp /etc/default/go-server /tmp/newconf.$$
sudo chmod 666 /tmp/newconf.$$

java_home=/usr/lib/jvm/$(ls /usr/lib/jvm/ | egrep "java-.*-openjdk-.*$")/jre
[ -d "$java_home" ] || fail "Could not figure out JAVA_HOME directory - please check the script"
[ -x "$java_home/bin/java" ] || fail "Could not find java executable in JAVA_HOME ($java_home) - please check the script"

export JAVA_HOME="$java_home"
cat <<EEE >>/tmp/newconf.$$
export JAVA_HOME="$java_home"
EEE

sudo cp /tmp/newconf.$$ /etc/default/go-server

echo
echo "If this is a server install, generating ssh-key for git pushes from
server (config files are git pushed as a backup)."

sudo su go ssh-keygen

echo "Setting up a remote to push config file backups"
CONFIG_REMOTE=git@github.com:genivigo/server-config-backup.git

cd /var/lib/go-server/db/config.git && sudo su go -c "git remote add backup $CONFIG_REMOTE"
cd /var/lib/go-server/db/config.git && sudo su go -c "git config push.default simple"

echo "Adding hourly crontab job to push config changes"

CRONSCRIPT=/etc/cron.hourly/go-config-push-backup
sudo cat <<XXX >$CRONSCRIPT
#!/bin/sh

# Backup (push) server config to git repo
su go -c "cd /var/lib/go-server/db/config.git && git push backup master"

# Pull down new custom commands, if they were added to git repo
su go -c "cd /var/lib/go-server/db/command_repository/genivi && git pull origin master"
XXX
sudo chmod 755 $CRONSCRIPT

echo Try running with 
echo 'sudo su go -c "/etc/init.d/go-server start"'

