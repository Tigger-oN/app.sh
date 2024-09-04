#!/bin/sh
# Helper script for working with the local ports tree.
# 
# Version
APP_VERSION="2024-09-04"
# It is assumed ports tree is located here. We check anyway.
PORTS_DIR="/usr/ports"
# Which INDEX is in use? This is used to check the status of apps and more.
PORT_INDEX="${PORTS_DIR}/INDEX-"`freebsd-version -r | awk -F'.' '{print $1}'`
# Where are the ports downloaded to?
PORT_DISTFILES="${PORTS_DIR}/distfiles"
# Used with each port while it is being worked on.
PORT_PATH=""
# Used to keep track of the requested ports and their status
APP_LIST=""
APP_SKIP=""
# CMD is used with commands that require at least one port to be passed
CMD=""
# Was there an issue that could wait?
ISSUE=""
ISSUE_FOUND=0
# We pass the out of date list around
OUT_OF_DATE=""

usage () {
	out="
Helper script for working with the local ports tree.
 
    ${0##*/} [abandoned | appvers | auto | distclean | old | pull | setup | work]
    ${0##*/} command port1 [port2...]
 
command is required and must be one of the following:
 
 A | abandoned : Use result with caution. Check for out of date ports that *may
                 not* be in use.
 a | auto      : Without confirmation, get the latest ports tree, then update
                 any that are out of date.
 C | distclean : Remove the ports/distfiles data for the passed port(s) or all
                 ports if no port is passed.
 h | help      : Show this help and exit.
 o | old       : List any out-of-date ports.
 p | pull      : Get the most recent version of the ports, then show which can 
                 be updated.
 S | setup     : Setup the local ports tree. Should only be needed once.
 V | appvers   : Show the script version and some basic information.
 W | work      : Look for any \"work\" subdirectories and clean them if found.
                 This is a best guess process.

The following commands require at least one port name to be passed.

 b | build     : Configure (if needed) and build (but not install) the requested
                 application(s).
 c | config    : Set configuration options for a port only.
 d | rm | del | delete | remove :
                 (Recommended) Delete the requested port(s) using
                 \"pkg delete <port>\". Will remove all related port(s). A
                 confirmation is required.
 D | deinstall : Use \"make deinstall\" in the port tree directory. Only the
                 requested port will be removed.
 i | add | install :
                 For new installs only. Configure, build and install the
                 requested port(s).
 r | u | reinstall | update :
                 For ports already installed. Reinstall / update the requested 
                 port(s).
 s | showconf  : Show the configuration options for a port only.

Port name is the \"base name\" of the port. Do not included the current version
or the new version numbers. For example, to update vim to the latest version 
(assuming already installed):

    ${0##*/} r vim
"
	printf "%s\n" "${out}"
    exit
}

error () {
    printf "\nProblem:\n"
    for x in "$@"
    do
        if [ ${#x} -gt 80 ]
        then
            lng=0
            for w in $x
            do
                lng=$((1 + lng + ${#w}))
                if [ ${lng} -gt 80 ]
                then
                    printf "\n"
                    lng=0
                fi
                printf "%s " "${w}"
            done
            printf "\n\n"
        else
            printf "%s\n\n" "${x}"
        fi
    done
    exit
}

workMsg () {
    printf "\nWorking on %s...\n" "${1}"
}

# Used to keep track of problems, but save the report until the end.
issueChk () {
    ISSUE_FOUND=0
    if [ "${1}" != "0" ]
    then
        ISSUE="${ISSUE}
 ${2}"
        ISSUE_FOUND=1
    fi
}

# Use the port index to locate the correct path for the port
getPortPath () {
    PORT_PATH=`awk -F'|' '$1 ~ /^'${1}'-([0-9._])+/ && !/^'${1}'-([0-9._])+([\-])+/ {print $2}' "${PORT_INDEX}" | uniq`
}

# Expects $@ to be passed. Should be called before a port cmd 
getAppList () {
    checkINDEX
    # Get the list of apps
    shift
    # Because there could be a delay...
    printf "\nChecking for requested port(s)...\n"
    for a in $@
    do
        result=`awk -F'|' '$1 ~ /^'${a}'-([0-9._])+/ && !/^'${a}'-([0-9._])+([\-])+/ {print $2}' "${PORT_INDEX}" | uniq | wc -l`
        if [ $result -eq 1 ]
        then
            APP_LIST=${APP_LIST}${a}" "
        else
            APP_SKIP=${APP_SKIP}" "${a}"
"
        fi
    done
    if [ -n "${APP_SKIP}" ]
    then
        printf "\nThe following are invalid.\n%s\nSkip these and continue [s|enter] or cancel [c]: " "${APP_SKIP}"
        read ans
        if [ "${ans}" = "c" -o "${ans}" = "C" ]
        then
            printf "\nExiting as requested.\n\n"
            exit
        else
            printf "\nSkipping invalid port(s) and continuing...\n"
        fi
    fi
}

checkAfterRun () {
    if [ -n "${ISSUE}" ]
    then
        printf "All done but had the following issue(s):\n%s\n\n" "${ISSUE}"
    else
        printf "All done.\n\n"
    fi
}

checkBeforeRun () {
    if [ ! "${1}" ]
    then
        usage
    fi
    # Simple check
    if [ ! -d "${PORTS_DIR}" ]
    then
        printf "\nUnable to locate the ports tree. Was checking here:\n"
        printf " %s\n" "${PORTS_DIR}"
        printf "\nIf you have installed the ports tree somewhere else, please edit \"PORTS_DIR\"\nin this script.\n"
        printf "\nIf you do not have a ports tree yet, please make the directory then run the\n\"setup\" command.\n\n"
        exit
    fi
    # Check the request is valid
    CMD=""
    case ${1} in
        A|abandoned) cmdAbandonded; return;;
        a|auto) cmdAuto; return;;
        b|build) CMD="cmdBuild";;
        C|distclean) cmdDistClean $@; return;;
        c|config) CMD="cmdConfig";;
        D|deinstall) CMD="cmdDeinstall";;
        d|rm|del|delete|remove) CMD="cmdDelete";;
        i|add|install) CMD="cmdInstall";;
        o|old) cmdOutOfDate; cmdDisplayOutOfDate; return;;
        p|pull) cmdPull; cmdDisplayOutOfDate; return;;
        r|u|reinstall|update) CMD="cmdReinstall";;
        S|setup) cmdSetup; return;;
        s|showconf) CMD="cmdConfigShow";;
        V|appvers) cmdAppVersion; return;;
        W|work) cmdWorkClean; return;;
        *) usage; return;;
    esac

    # Still here? Then we have a command request that needs at least one port
    if [ ! "${2}" ]
    then
        error "That request requires at least one port to be passed."
    fi

    getAppList $@

    if [ -z "${APP_LIST}" ]
    then
        error "No valid ports found for your request."
    fi
}

checkINDEX () {
    if [ ! -f "${PORT_INDEX}" ]
    then
        error "Unable to locate the port index." "This should have been downloaded after a \"pull\" request." "Was looking for: ${PORT_INDEX}" "You may need to run \"cd ${PORTS_DIR} ; make fetchindex\" first."
    fi
}

checkGit () {
    if [ -z `which git` ]
    then
        error "Unable to locate git. Is it installed?" "You can install git from an existing ports tree (better, slower) or as a binary (much faster) with \"pkg install git\"."
    fi
}

checkRoot () {
    if [ `whoami` != "root" ]
    then
        error "This request must be performed as the root user."
    fi
}

# Checks done by setup
checkSetup () {
    checkRoot
    checkGit
    if [ `ls "${PORTS_DIR}" | wc -l` -gt 0 ]
    then
        error "${PORTS_DIR} is not empty." "The current ports tree must be empty to start the setup process." "Did you mean to \"pull\" (update) the ports tree instead?"
    fi
}

checkPull () {
    checkRoot
    checkGit
    if [ -z `ls "${PORTS_DIR}" | head -1` ]
    then
        error "Looks like the ports directory is empty." "Have you run setup yet?"
    fi
    cd "${PORTS_DIR}"
    CHK=`git rev-parse --is-inside-work-tree`
    if [ "$?" = "128" ]
    then
        error "Looks like "${PORTS_DIR}" is not a git repository." "Please remove all the ports and run setup first."
    fi
}

# Try to locate any ports that are not used and are out of date.
cmdAbandonded () {
    cmdOutOfDate
    if [ -z "${OUT_OF_DATE}" ]
    then
        printf "\nNo out of date ports. This feature requires at least one out of date port.\n\n"
        exit
    fi
    printf "\nChecking for standalone and out of date ports...\n"
    abList=""
    tmp=""
    for p in ${OUT_OF_DATE}
    do
        #printf " %s\n" "${p}"
        tmp=`pkg delete -n -R "${p}" | grep "Number of packages to be removed" | awk '{print $NF}'`
        if [ "${tmp}" = "1" ]
        then
            abList="
 ${p}"
        fi
    done
    if [ -n "${abList}" ]
    then
        printf "\nThe following port(s) require an update but do not appear to be used or\nrequired by any other ports:\n%s\n\n" "$abList"
    else
        printf "\nAll out of date port(s) are required by at least one other installed port.\n\n"
    fi
    exit
}

cmdAppVersion () {
    if [ -f "${PORTS_DIR}/.git/refs/heads/main" ]
    then
        tmp=`date -r "${PORTS_DIR}/.git/refs/heads/main"`
    else
        tmp="No pull requests made."
    fi
    printf "\nApp version      %s\n" "${APP_VERSION}"
    printf "Ports directory  %s\n" "${PORTS_DIR}"
    printf "Ports INDEX      %s\n" "${PORT_INDEX##*/}"
    printf "Last pull        %s\n\n" "${tmp}"
    exit
}

cmdAuto () {
    printf "\nWill get the latest ports tree, check for any out of date ports and update\nthem if found.\n"
    checkRoot
    checkGit
    cmdPull

    if [ -n "${OUT_OF_DATE}" ]
    then
        printf "\nThe following ports are out of date and will be updated.\n%s\n" "${OUT_OF_DATE}"
        printf "\nCTRL+c to cancel, otherwise starting in: 3..."
        sleep 1
        printf "2..."
        sleep 1
        printf "1..."
        sleep 1
        printf "\n"
    else
        printf "\nAll ports are up to date.\n\n"
        exit
    fi

    # At this point we have at least one port to update
    for a in `printf "%s" "${OUT_OF_DATE}" | awk -F'-[0-9]' '{print $1}'`
    do
        APP_LIST=${APP_LIST}${a}" "
    done
    # Run a conditional config check
    subMakeConfigForBuild
    # Start the update for each app
    cmdReinstall
    # Because cmdAuto runs a little different
    checkAfterRun
    exit
}

cmdBuild () {
	checkRoot
    printf "\nBuild started.\n"
    subMakeClean
    printf "\nConfig option check.\n"
    subMakeConfigForBuild
    printf "\nBuilding port.\n"
    subMakeBuild
}
# Set the config options for all the passed ports.
# NOTE: This is different from the subConfigConditional call as a config
# request is always performed. This request can be called directly.
cmdConfig () {
    printf "\nConfig started\n"
    for p in ${APP_LIST}
    do
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make config
        issueChk "$?" "${p} - make config"
    done
}
# Show the config options for all the passed ports.
cmdConfigShow () {
    printf "\nShow configuration started\n"
    for p in ${APP_LIST}
    do
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make showconfig
        issueChk "$?" "${p} - make showconfig"
    done
}
# Delete the requested port(s) using pkg delete <port(s)>
cmdDelete () {
    pkg delete ${APP_LIST}
}
# Deinstall the port(s) using make deinstall
cmdDeinstall () {
    printf "\nDeinstalling the requested port(s).\n"
    for p in ${APP_LIST}
    do
        printf "\nWorking on %s...\n" "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make clean ; make deinstall
        issueChk "$?" "${p} - make deinstall"
    done
}
# Removes the ports/dist files for the passed ports or all ports.
cmdDistClean () {
    checkRoot
    # simple check
    if [ ! -d "${PORT_DISTFILES}" ]
    then
        error "Unable to locate the ports/distfiles directory." "Was looking here: ${PORT_DISTFILES}" "If you have this directory somewhere else your will need to edit this script." "Alternatively you can \"rm -r /path/to/distfiles/*\""
    fi
    # All ports or just passed ports?
    if [ $# -gt 1 ]
    then
        getAppList $@
        if [ -z "${APP_LIST}" ]
        then
            printf "\nNo matching port(s) to clean for. Guess we are done for now.\n\n"
            exit
        fi
        for p in ${APP_LIST}
        do
            getPortPath "${p}"
            printf "\nCleaning ports/distfiles for %s...\n" "${p}"
            cd "${PORT_PATH}"
            make distclean
        done
    else
        printf "\nConfirmation required.\n\nDo you really want to remove all ports/distfiles? [Y/n] "
        read ans
        if [ "${ans}" = "n" -o "${ans}" = "N" ]
        then
            printf "\nNothing else to do, exiting.\n\n"
            exit
        else
            printf "\nRemoving all of the ports/distfiles...\n"
            rm -vrf ${PORT_DISTFILES}/*
        fi
    fi
    printf "\nAll done.\n\n"
    exit
}
# Display any out of date ports. Used AFTER cmdOutOfDate (or not).
cmdDisplayOutOfDate () {
    if [ -n "${OUT_OF_DATE}" ]
    then
        tmp=""
        warn="
---------------------------
IMPORTANT: Recompile first:"
        tmpPkg=`printf "%s" "${OUT_OF_DATE}" | grep "^pkg-"`
        tmpRst=`printf "%s" "${OUT_OF_DATE}" | grep "^rust-"`
        if [ -n "$tmpPkg" -a -n "$tmpRst" ]
        then
            tmp="${warn} pkg, then rust"
        elif [ -n "$tmpPkg" ]
        then
            tmp="${warn} pkg"
        elif [ -n "$tmpRst" ]
        then
            tmp="${warn} rust"
        fi
        printf "\nFound:\n%s\n\n" "${OUT_OF_DATE}${tmp}"
    else
        printf "\nAll ports are up to date.\n\n"
    fi
}
# Configure, build and install a port
cmdInstall () {
    printf "\nInstall started, cleaning first.\n"
    subMakeClean
    printf "\nConfig option check.\n"
    subMakeConfigForBuild
    printf "\nBuild and install started\n"
    subMakeInstall
}
# Check for any out of date ports. OUT_OF_DATE will hold the output.
cmdOutOfDate () {
    checkINDEX
    printf "\nChecking for out of date ports.\n"
    OUT_OF_DATE=`pkg version -vI -l '<'`
}
# Get the latest ports tree
cmdPull () {
    printf "\nChecking a few things first...\n"
    checkPull

    printf "\nRunning fetch and checking if an update is required...\n"
    git -C "${PORTS_DIR}" fetch
    CHK=`git -C "${PORTS_DIR}" rev-list HEAD...origin/main --count`

    # Is a pull request needed?
    if [ ${CHK} -eq 0 ]
    then
        printf "\nPorts tree is up to date.\n"
        if [ ! -f "${PORT_INDEX}" ]
        then
            subMakeFetchIndex
        fi
    else 
        printf "\nStarting the pull request...\n"
        git -C "${PORTS_DIR}" pull
        printf "\nPorts have been updated.\n"
        subMakeFetchIndex
        printf "\nPorts tree should be up to date.\n"
    fi
    # Check if anything out of date
    cmdOutOfDate
}
# Reinstall / update requested port(s)
cmdReinstall () {
    printf "\nReinstall started\n"
    local issue=0
    # Clean all the ports first.
    subMakeClean
	# Conditional config check
	subMakeConfigForBuild
	# Start the real update
    for p in ${APP_LIST}
    do
        issue="0"
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make
        issue="$?"
        if [ ${issue} != "0" ]
        then
            issueChk "1" "${p} - make"
            continue
        fi
        make reinstall
        issue="$?"
        if [ ${issue} != "0" ]
        then
            issueChk "1" "${p} - make reinstall"
            continue
        else
            INSTALLED="${INSTALLED}
 ${p}"
        fi
        make clean
    done
}

# Use git to pull down the ports
cmdSetup () {
    printf "\nChecking a few things first...\n"
    checkSetup
    printf "\nReady to clone. This will take some time...\n"
    git clone --depth 1 https://git.FreeBSD.org/ports.git "${PORTS_DIR}"
    subMakeFetchIndex
    printf "\nThe ports tree has been setup. Use \"pull\" to keep the ports tree in sync.\n\n"
    exit
}
# Look for any work directories in a port, list, then clean them.
# How does this happen? Build failures are my guess.
cmdWorkClean () {
    checkRoot
    printf "\nLooking for stray \"work\" directories...\n"
    WORK=`find ${PORTS_DIR} -type d -name "work*" -depth 3`
    if [ -n "${WORK}" ]
    then
        for w in ${WORK}
        do
            p=${w%/work*}
            p=${p##*/}
            APP_LIST=${APP_LIST}${p##*/}" "
        done
        printf "\nFound \"work\" directories for the following:\n"
        printf " %s\n" ${APP_LIST}
        subMakeClean
        printf "\n"
        checkAfterRun
    else
        printf "\nNo \"work\" directories found. This does not mean everything is clean, just\na best guess.\n\n"
    fi
    exit
}

subMakeBuild () {
    # Note: Assumes subMakeClean has been run.
    for p in ${APP_LIST}
    do
        printf "\nWorking on %s...\n" "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make
        issueChk "$?" "${p} - make"
    done
}
# Clean the build working directory. While it may not always be needed, it is
# safer to do this every time.
# TODO: Make this optional? For example: if a build has failed, this will
# require the build to start from scratch when it may not be needed.
subMakeClean () {
    for p in ${APP_LIST}
    do
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make clean
        issueChk "$?" "${p} - make clean"
    done
}
# Used with "build" commands. Will try to set all config options up front
# before starting to build the port(s).
subMakeConfigForBuild () {
    for p in ${APP_LIST}
    do
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        #make config-recursive
        make config-conditional
    done
}

subMakeFetchIndex () {
    printf "\nGetting the latest port INDEX file...\n"
    cd "${PORTS_DIR}"
    make fetchindex
}

subMakeInstall () {
    # Note: Assumes subMakeClean has been run.
    local issue=0
    for p in ${APP_LIST}
    do
        issue="0"
        workMsg "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make
        issue="$?"
        if [ ${issue} != "0" ]
        then
            issueChk "1" "${p} - make"
            continue
        fi
        make install
        issue="$?"
        if [ ${issue} != "0" ]
        then
            issueChk "1" "${p} - make install"
            continue
        else
            INSTALLED="${INSTALLED}
 ${p}"
        fi
        make clean
    done
}

# A few checks before going further
checkBeforeRun "$@"

# At this point, we should have a CMD that requires at least one port.
${CMD} 

# Should be done, but was there any issues?
checkAfterRun
exit

