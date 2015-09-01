#!/bin/bash

if ! [ -f /.dockerinit ]; then
  echo "Not running inside docker, exiting to avoid data damage." >&2
  exit 1
fi

set -e
set -u

ORIG_DIR='/code'
PASSWORD="selenium"

if [ -z "${1:-}" ] ; then
  echo "Usage: $0 <testsystem>" >&2
  echo
  echo "Usage example: $0 192.168.88.162"
  exit 1
fi

SERVER="${1}"

# vnc
echo "Setting VNC password"
printf '%s\n%s\n\n' "${PASSWORD}" "${PASSWORD}" | vncpasswd >/dev/null
xvnc_process=$(pgrep -f 'Xvnc4 :99' || true)
if [ -n "${xvnc_process:-}" ] ; then
  echo "Warning: existing VNC server found, not restarting."
  # kill $xvnc_process
else
  echo "Starting VNCserver on display :99"
  vncserver -geometry 1280x1024 :99
fi

# selenium
selenium_process=$(pgrep -f '/usr/bin/java -jar /home/selenium/selenium-server-standalone.jar' || true)
[ -n "${selenium_process:-}" ] && kill $selenium_process
# TODO this could silently fail but selenium-server-standalone.jar is missing a daemonize option
DISPLAY=:99 /usr/bin/java -jar /home/selenium/selenium-server-standalone.jar -trustAllSSLCertificates -log /home/selenium/selenium.log &

# preparation
cd /tmp/
rm -rf ngcp-schema
git clone  git://git.mgm.sipwise.com/ngcp-schema
cd ngcp-schema
export SCHEMA_LOCATION=$(pwd)
perl Build.PL
./Build

cd /tmp
rm -rf sipwise-base
git clone git://git.mgm.sipwise.com/sipwise-base
cd sipwise-base
export SIPWISE_BASE_LOCATION=$(pwd)
perl Build.PL
./Build

# test execution
cd "$ORIG_DIR"
export PERL5LIB="${SCHEMA_LOCATION}/lib:${SIPWISE_BASE_LOCATION}/lib"
perl ./Build.PL

echo "################################################################################"
echo "Finished main setup, now running tests ..."
echo "Selenium server log file available at /home/selenium/selenium.log"
echo "Watch at test runs by connecting via VNC (enter password '${PASSWORD}'):"
echo "vncviewer geometry=1280x1024x16 \$(docker inspect \$(docker ps -l -q) | jq -r '.[0].NetworkSettings.IPAddress'):5999"

RC=0
#./Build test_selenium --schema-base-dir="$SCHEMA_LOCATION" --server="https://${SERVER}:1443" --webdriver=external --wd-server=http://127.0.0.1:4444 > /home/selenium/junit.xml || RC=$?
CATALYST_SERVER="https://${SERVER}:1443/" prove -PSetEnv=PERL5LIB="${PERL5LIB}" -PSetEnv=TEST_PRETTY_COLOR_NAME=white -PSetEnv=PERL_LWP_SSL_VERIFY_HOSTNAME=0 --color -Pretty -l -It/lib t/selenium/admin-login.t || RC=$?
#CATALYST_SERVER=https://10.15.20.167:1443/ prove -PSetEnv=PERL5LIB=/tmp/sipwise-base/lib:/tmp/ngcp-schema/lib -PSetEnv=TEST_PRETTY_COLOR_NAME=white -PSetEnv=PERL_LWP_SSL_VERIFY_HOSTNAME=0 --formatter TAP::Formatter::JUnit -l -It/lib t/selenium/admin-login.t || RC=$?

echo "Finished test execution, test execution returned with exit code $RC"
echo "Test results available in /home/selenium/junit.xml"
echo "################################################################################"
