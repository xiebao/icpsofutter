#!/usr/bin/env sh

##############################################################################
##
##  Gradle start up script for UN*X
##
##############################################################################

# Attempt to set APP_HOME
# Resolve links: $0 may be a link
PRG="$0"
while [ -h "$PRG" ] ; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`"/$link"
  fi
 done
SAVED="`pwd`"
cd "`dirname \"$PRG\"`/.." > /dev/null
APP_HOME="`pwd -P`"
cd "$SAVED" > /dev/null

APP_NAME="Gradle"
APP_BASE_NAME=`basename "$0"`

# Add default JVM options here. You can also use JAVA_OPTS and GRADLE_OPTS to pass JVM options to this script.
DEFAULT_JVM_OPTS=""

# Use the maximum available, or set MAX_FD != -1 to use that value.
MAX_FD="maximum"

warn () {
    echo "$*"
}

# OS specific support. $var _must_ be set to either true or false.
cygwin=false
msys=false
darwin=false
case "`uname`" in
  CYGWIN* ) cygwin=true ;;
  Darwin* ) darwin=true ;;
  MINGW* ) msys=true ;;
esac

# For Cygwin or MSYS, switch paths to Windows format before running java
if $cygwin ; then
  APP_HOME=`cygpath --path --mixed "$APP_HOME"`
  CLASSPATH=`cygpath --path --mixed "$CLASSPATH"`
fi
if $msys ; then
  APP_HOME=`(cd "$APP_HOME"; pwd)`
fi

# Determine the Java command to use to start the JVM.
if [ -n "$JAVA_HOME" ] ; then
    if [ -x "$JAVA_HOME/jre/sh/java" ] ; then
        # IBM's JDK on AIX uses strange locations for the executables
        JAVACMD="$JAVA_HOME/jre/sh/java"
    else
        JAVACMD="$JAVA_HOME/bin/java"
    fi
    if [ ! -x "$JAVACMD" ] ; then
        warn "ERROR: JAVA_HOME is set to an invalid directory: $JAVA_HOME"
        warn "Please set the JAVA_HOME variable in your environment to match the location of your Java installation."
        exit 1
    fi
else
    JAVACMD="java"
fi

# Increase the maximum file descriptors if we can.
if [ "$cygwin" = "false" -a "$msys" = "false" ]; then
    MAX_FD_LIMIT=`ulimit -H -n`
    if [ $? -eq 0 ]; then
        if [ "$MAX_FD" = "maximum" ] || [ "$MAX_FD" = "max" ]; then
            MAX_FD="$MAX_FD_LIMIT"
        fi
        ulimit -n $MAX_FD
        if [ $? -ne 0 ]; then
            warn "Could not set maximum file descriptor limit: $MAX_FD"
        fi
    else
        warn "Could not query maximum file descriptor limit: $MAX_FD_LIMIT"
    fi
fi

# For Darwin, add options to specify how the application appears in the dock
if $darwin; then
    GRADLE_OPTS="$GRADLE_OPTS -Xdock:name=$APP_NAME -Xdock:icon=$APP_HOME/media/gradle.icns"
fi

# Escape application args
save () {
    for i; do
        printf '%s\n' "$i" | sed \
            -e 's/'"'"'/'"'\\''"'/g' \
            -e "s/\"/'\\\"'/g"
    done
}

APP_ARGS=("$@")

# Collect all arguments for the java command, following the shell quoting and escaping rules
JAVA_ARGS=( )
for arg in "${APP_ARGS[@]}"; do
    JAVA_ARGS+=("$arg")
done

exec "$JAVACMD" $DEFAULT_JVM_OPTS $JAVA_OPTS $GRADLE_OPTS -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "${JAVA_ARGS[@]}" 