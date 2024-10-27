#!/bin/sh
# Helper script for working with the local ports tree.
#
# TODO: Need to clean up the options. Some processes are being run twice.
# 
# Version - yyyymmdd format of the last change
APP_VERSION="20241027"
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
    app=${0##*/}
    out="
Helper script for working with the local ports tree.
 
    ${app} [abandoned | appvers | auto | distclean | fetchindex | old | pull 
           | setup | work]
    ${app} command port1 [port2...]
 
command is required and must be one of the following:
 
 a | abandoned : Use result with caution. Check for any superseded ports that 
                 *may not* be in use.
 A | auto      : Without confirmation, get the latest ports tree then update any
                 that have been superseded.
 C | distclean : Remove the ports/distfiles data for the passed port(s) or all
                 ports if no port is passed.
 F | fetchindex: Download the latest ports index.
 h | help      : Show this help and exit.
 o | old       : List any superseded ports.
 p | pull      : Get the most recent version of the ports, then show which can 
                 be updated.
 S | setup     : Setup the local ports tree. Should only be needed once.
 V | appvers   : Show the script version and some basic information.
 W | work      : Look for any \"work\" subdirectories and clean them if found.
                 This is a best guess process.

The following commands require at least one port name to be passed.

 b | build     : Configure (if needed) and build but not install the requested
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

    ${app} r vim
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
    exit 1
}

workMsg () {
    printf "\n[%s] %s...\n" "${1}" "${2}"
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
        printf "\nAll done but had the following issue(s):\n%s\n\n" "${ISSUE}"
    else
        printf "\nAll done.\n\n"
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
        printf "\nUnable to locate the ports tree. Was checking here:\n\n\
 %s\n\n\
If you have installed the ports tree somewhere else, please edit \"PORTS_DIR\"\n\
in this script.\n\n\
If you do not have a ports tree yet, please make the directory then run the\n\
\"setup\" command.\n\n" "${PORTS_DIR}"
        exit 1
    fi
    # Check the request is valid
    CMD=""
    case ${1} in
        a|abandoned) cmdAbandonded; return;;
        A|auto) cmdAuto; return;;
        b|build) CMD="cmdBuild";;
        C|distclean) cmdDistClean $@; return;;
        c|config) CMD="cmdConfig";;
        D|deinstall) CMD="cmdDeinstall";;
        d|rm|del|delete|remove) CMD="cmdDelete";;
        F|fetchindex) cmdFetchIndex; return;;
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
        printf "\nNo superseded ports. This feature requires at least one out of date port.\n\n"
        exit
    fi
    printf "\nChecking for standalone and out of date ports...\n"
    abList=""
    tmp=""
    for p in ${OUT_OF_DATE}
    do
        tmp=`pkg delete -n -R "${p}" | grep "Number of packages to be removed" | awk '{print $NF}'`
        if [ "${tmp}" = "1" ]
        then
            abList="${abList}
 ${p}"
        fi
    done
    if [ -n "${abList}" ]
    then
        printf "\nUpdate available for the following standalone port(s):\n%s\n\n" "$abList"
    else
        printf "\nAny out of date port is required by at least one other installed port.\n\n"
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
    printf "\n\
App version      %s\n\
Ports directory  %s\n\
Ports INDEX      %s\n\
Last pull        %s\n\
\n" "${APP_VERSION}" "${PORTS_DIR}" "${PORT_INDEX##*/}" "${tmp}"
    exit
}

cmdAuto () {
    checkRoot
    printf "\nWill get the latest ports tree, check for any out of date ports and update\nthem if found.\n"
    checkGit
    cmdPull

    if [ -n "${OUT_OF_DATE}" ]
    then
        printf "\nFound an update for following port(s):\n\n%s\n" "${OUT_OF_DATE}"
        printf "\nCTRL+c to cancel, otherwise updating port(s) in: "
        subCountDown 3
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
    # Make sure everything is clean
    subCmd "clean"
    # Run a conditional config check
    subCmd "config-conditional"
    # Start the update for each app
    subCmd "reinstall"
    # Clean up
    subCmd "clean"
    # Because cmdAuto runs a little different
    checkAfterRun
    exit
}
# NOTE: No clean is performed after the build.
cmdBuild () {
    checkRoot
    printf "\nBuild started.\n"
    subCmd "clean"
    printf "\nConfig option check.\n"
    subCmd "config-conditional"
    printf "\nBuilding port.\n"
    subCmd "build"
}
# Set the config options for all the passed ports.
# NOTE: This is different from the subConfigConditional call as a config
# request is always performed. This request can be called directly.
cmdConfig () {
    printf "\nConfig started\n"
    subCmd "config"
}
# Show the config options for all the passed ports.
cmdConfigShow () {
    printf "\nShow configuration started\n"
    subCmd "showconfig"
}
# Delete the requested port(s) using pkg delete <port(s)>
cmdDelete () {
    pkg delete ${APP_LIST}
}
# Deinstall the port(s) using make deinstall
cmdDeinstall () {
    printf "\nDeinstalling the requested port(s).\n"
    subCmd "deinstall"
}
# Removes the ports/dist files for the passed ports or all ports.
# Note: distclean also cleans the port dir
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
        subCmd "distclean"
    else
        # Are there any files to remove?
        local c=`ls -Aq "${PORT_DISTFILES}" | wc -l`
        if [ $c -eq 0 ]
        then
            printf "\nThe ports/distfiles are clean already. Nothing to do here.\n\n"
            exit
        fi
        # Still here? We have files then.
        printf "\nCurrent disk usage:\n\n%s\n" "`du -hc "${PORT_DISTFILES}"`"
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
        printf "\nFound an update for the following port(s):\n\n%s\n\n" "${OUT_OF_DATE}${tmp}"
    else
        printf "\nAll ports are up to date.\n"
    fi
}
# Grab the latest ports index without a pull request.
cmdFetchIndex () {
    warn="
Grab the latest ports index without a \"pull\" request. This could lead to the
ports tree being out of sync with the ports index.

Only perform this request if there was an error previously.

Understand the risk and continue? (Y/n) : "
    printf "%s" "${warn}"
    read ans
    if [ "${ans}" = "y" -o "${ans}" = "Y" -o "${ans}" = "" ]
    then
        subMakeFetchIndex
    else
        printf "\nCancelling \"fetchindex\" request.\n\n"
        exit
    fi
}
# Configure, build and install a port
cmdInstall () {
    printf "\nInstall started, cleaning first.\n"
    subCmd "clean"
    printf "\nConfig option check.\n"
    subCmd "config-conditional"
    printf "\nBuild and install started\n"
    subCmd "install"
    subCmd "clean"
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

    printf "\nRunning fetch and checking if an update is required...\n\n"
    git -C "${PORTS_DIR}" fetch
    if [ $? -gt 0 ]
    then
        printf "\nUnable to perform a \"git fetch\" request. This is a major issue.\n\
\nPlease check network connection and harddrive space then try again.\n\n"
        exit 1
    fi
    CHK=`git -C "${PORTS_DIR}" rev-list HEAD...origin/main --count`
    # Is a pull request needed?
    if [ ${CHK} -eq 0 ]
    then
        printf "Ports tree is up to date.\n"
        if [ ! -f "${PORT_INDEX}" ]
        then
            subMakeFetchIndex
        fi
    else 
        printf "\nStarting the pull request...\n\n"
        git -C "${PORTS_DIR}" pull
        if [ $? -eq 0 ]
        then 
            printf "\nPorts tree has been updated.\n"
        else
            issueChk "$?" "\"git pull\" failed in some way. Guessing network connection or harddrive space."
        fi
        subMakeFetchIndex
        if [ $? -gt 0 ]
        then
            printf "\nThere was an issue getting the ports index.\n\
\nRun \"%s fetchindex\" to resolve the issue.\n\n" "${0##*/}"
        fi
    fi
    # Check if anything out of date
    cmdOutOfDate
}
# Reinstall / update requested port(s)
cmdReinstall () {
    printf "\nReinstall started\n"
    local issue=0
    # Clean all the ports first.
    subCmd "clean"
    # Conditional config check
    subCmd "config-conditional"
    # Start the real update
    subCmd "reinstall"
    # And clean up
    subCmd "clean"
}
# Use git to pull down the ports
cmdSetup () {
    printf "\nChecking a few things first...\n"
    checkSetup
    printf "\nReady to clone. This will take some time...\n\n"
    git clone --depth 1 https://git.FreeBSD.org/ports.git "${PORTS_DIR}"
    if [ $? -gt 0 ]
    then
        printf "\nUnable to perform \"git clone\". This is a major issue.\n\
\nTry running setup again. You may need to delete the contents of:\n\
 %s\n\n" "${PORTS_DIR}"
        exit 1
    fi
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
        subCmd "clean"
        printf "\n"
        checkAfterRun
    else
        printf "\nNo \"work\" directories found. This does not mean everything is clean, just\na best guess.\n\n"
    fi
    exit
}

# Will loop over APP_LIST and perform an action
subCmd () {
    if [ -z "${1}" ]
    then
        error "Script error. subCmd called without an action definded."
    fi
    local action=""
    local action2=""
    local issue=0
    local subAction="${1}"
    case "${1}" in
        build) break;;
        clean) action="clean"; break;;
        config) action="config"; break;;
        config-conditional) action="config-conditional"; break;;
        distclean) action="distclean"; break;;
        deinstall) action="clean"; action2="deinstall"; break;;
        install) action2="install"; break;;
        reinstall) action2="reinstall"; break;;
        showconfig) action="showconfig"; break;;
        *) error "Script error. SUB_ACTION is invalid.";;
    esac

    for p in ${APP_LIST}
    do
        issue=0
        workMsg "${subAction}" "${p}"
        getPortPath "${p}"
        cd "${PORT_PATH}"
        make ${action}
        issue="$?"
        if [ ${issue} != "0" ]
        then
            issueChk "${issue}" "${p} - make ${action}"
            continue
        fi
        if [ -n "${action2}" ]
        then
            make ${action2}
            issueChk "$?" "${p} - make ${action2}"
        fi
    done
}
# Visual pause
subCountDown () {
    local c=3
    local t=0
    if [ -n "${1}" -a ${1} -gt 0 ]
    then
        c=${1}
    fi
    while [ $c -gt 0 ]
    do
        printf "%s" "${c}"
        c=$((c - 1))
        t=0
        sleep 0.25
        while [ $t -lt 3 ]
        do
            printf "."
            t=$((t + 1))
            sleep 0.25
        done
    done
}

subMakeFetchIndex () {
    printf "\nGetting the latest ports index file...\n\n"
    cd "${PORTS_DIR}"
    make fetchindex
    if [ $? -gt 0 ]
    then
        issueChk "1" "\"make fetchindex\" failed. Possible network issue."
        return 1
    else
        printf "\nPorts index file has been updated.\n"
        return 0
    fi
}

# A few checks before going further
checkBeforeRun "$@"

# At this point, we should have a CMD that requires at least one port.
${CMD} 

# Should be done, but was there any issues?
checkAfterRun
exit

