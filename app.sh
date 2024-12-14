#!/bin/sh
# Helper script for working with the local ports tree.
#
# TODO: 
# 
# Version - yyyymmdd format of the last change
APP_VERSION="20241214"
# It is assumed ports tree is located here. We check anyway.
PORTS_DIR="/usr/ports"
# Which INDEX is in use? This is used to check the status of apps and more.
PORT_INDEX="${PORTS_DIR}/INDEX-"`freebsd-version -r | sed 's/\..*//'`
# Where are the ports downloaded to?
PORT_DISTFILES="${PORTS_DIR}/distfiles"
# Used with each port while it is being worked on.
PORT_PATH=""
# Used to keep track of the requested ports and their status
APP_LIST=""
APP_SKIP=""
SEARCH_LIST=""
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
 
    ${app} [abandoned | auto | distclean | fetchindex | old | pull | setup 
            | verison | work]
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
 V | version   : Show the script version and some basic information.
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
 R | Reinstall : Search for a group of installed ports and reinstall them.
 s | showconf  : Show the configuration options for a port only.
 U | Update    : Search for a group of superseded ports and update them.

Port name is the \"base name\" of the port. Do not included the current version
or the new version numbers. For example, to update vim to the latest version 
(assuming already installed):

    ${app} r vim

Reinstall and Update (capital R/U) will search for and list all ports based on
a matched part of a port name. Helpful for updating a group of ports without
the need to type the entire list. Reinstall will search the installed list of
ports. Update will only look at superseded ports. You can search on more than
one term.
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
                    lng=${#w}
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
# Locate the correct path for the port
getPortPath () {
    PORT_PATH=`pkg query "${PORTS_DIR}/%o" "${1}"`
    if [ -z "${PORT_PATH}" ]
    then
        # May not have been install, locate another way
        PORT_PATH=`awk -F'|' '$1 ~ /^'${1}'-([0-9._])+/ && !/^'${1}'-([0-9._])+([\-])+/ {print $2}' "${PORT_INDEX}"`
    fi
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
        getPortPath "${a}"
        if [ -n "${PORT_PATH}" ]
        then
            APP_LIST=${APP_LIST}${a}" "
        else
            APP_SKIP=${APP_SKIP}" "${a}"
"
        fi
    done
    if [ -n "${APP_SKIP}" ]
    then
        printf "\nThe following are invalid.\n%s\nSkip these and continue [S/enter] or cancel [c]: " "${APP_SKIP}"
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
        R|Reinstall) cmdSearchReinstall $@; return;;
        s|showconf) CMD="cmdConfigShow";;
        S|setup) cmdSetup; return;;
        U|Update) cmdSearchUpdate $@; return;;
        V|version) cmdAppVersion; return;;
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

# Try to locate any ports that are not used by another and are out of date.
cmdAbandonded () {
    cmdOutOfDate
    if [ -z "${OUT_OF_DATE}" ]
    then
        printf "\nNo superseded ports. This feature requires at least one out of date port.\n\n"
        exit
    fi
    printf "\nChecking for standalone and out of date ports...\n"
    abList=""
    for p in `printf "%s" "${OUT_OF_DATE}" | sed 's/ .*//'`
    do
        if [ `pkg query "%#r" "${p}"` -eq 0 ] 
        then
            abList="${abList}
 ${p}"
        fi
    done
    if [ -n "${abList}" ]
    then
        printf "\nUpdate available for the following standalone port(s):\n%s\n\n" "$abList"
    else
        printf "\nSuperseded ports are required by at least one other installed port.\n\n"
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
    APP_LIST=`printf "%s" "${OUT_OF_DATE}" | sed 's/-[0-9].*//' | tr '\n' ' '`
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
    checkRoot
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
    checkRoot
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
        printf "\nFound an update for the following port(s):\n\n%s\n" "${OUT_OF_DATE}${tmp}"
    else
        printf "\nAll ports are up to date.\n"
    fi
}
# Grab the latest ports index without a pull request.
cmdFetchIndex () {
    checkRoot
    warn="
Grab the latest ports index without a \"pull\" request. This could lead to the
ports tree being out of sync with the ports index.

Only perform this request if there was an error previously.

Understand the risk and continue? [Y/n] : "
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
    checkRoot
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
    OUT_OF_DATE=`pkg version -vI -l'<' | sed 's/needs updating (\(.*\))/\1/'`
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
    checkRoot
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
# Search for all matching ports and reinstall.
# cmdSearchReinstall - will reinstall all the matched ports that have
# been installed previously.
# cmdSearchUpdate - only matched ports that have an update avaliable.
cmdSearchReinstall () {
    checkRoot
    if [ ! "${2}" ]
    then
        error "At least one search term is required. It should be the common part of the port(s) you want to reinstall."
    fi
    shift
    SEARCH_LIST=`pkg query -ix %n $@`

    subSearchReinstall $@
}
# pkg version -l'<' -ix "prot|boo" | sed 's/\(.*\)-.*/\1/'
cmdSearchUpdate () {
    checkRoot
    if [ ! "${2}" ]
    then
        error "At least one search term is required. It should be the common part of the port(s) you want to update."
    fi
    shift
    tmp=`echo "${@}" | sed 's/ /\|/g'`
    SEARCH_LIST=`pkg version -l'<' -ix "${tmp}" | sed 's/\(.*\)-.*/\1/'`
    subSearchReinstall $@
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
    found=`find ${PORTS_DIR} -type d -name "work*" -depth 3`
    if [ -n "${found}" ]
    then
        for w in ${found}
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
# Show a list of found ports and offer up some options
subSearchListConfirm () {
    ready=0
    while [ $ready -eq 0 ]
    do
        printf "\nFound the following matches:\n"
        i=1;
        for p in $SEARCH_LIST
        do
            printf " %2s) %s\n" "${i}" "${p}"
            i=$((i + 1))
        done
        max=$i

        printf "\nConfirmation required:\n
Begin [Y/enter] | Cancel [c/n/x] | Ignore [number] : "
        read ans
        if [ -z "${ans}" -o "${ans}" = "y" -o "${ans}" = "Y" ]
        then
            ready=1
            continue
        elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "x" -o "${ans}" = "X" ]
        then
            printf "\nRequest cancelled.\n\n"
            exit
        elif [ $ans -gt 0 -a $ans -lt $max ]
        then
            tmp=""
            i=1
            for x in $SEARCH_LIST
            do
                if [ $i -ne $ans ]
                then
                    if [ -z "${tmp}" ]
                    then
                        tmp="${x}"
                    else
                        tmp="${tmp}
${x}"
                    fi
                fi
                i=$((i + 1))
            done
            SEARCH_LIST="${tmp}"
        else
            printf "\nInvalid option. Try again.\n"
        fi

        if [ -z "${SEARCH_LIST}" ]
        then
            printf "\nNo ports left on the list!\n\n"
            exit
        fi
    done
}
# The common part of cmdSearchUpdate and cmdSearchReinstall
subSearchReinstall () {
    if [ -z "${SEARCH_LIST}" ]
    then
        printf "\nNo matches found for:\n"
        printf " %s\n" "${@}"
        printf "\n"
        exit
    fi

    subSearchListConfirm

    if [ -n "${SEARCH_LIST}" ]
    then
        APP_LIST=`printf "%s" "${SEARCH_LIST}" | tr '\n' ' '`
        cmdReinstall
    else
        printf "\nNothing to do here.\n\n"
    fi
    exit
}

# A few checks before going further
checkBeforeRun "$@"

# At this point, we should have a CMD that requires at least one port.
${CMD} 

# Should be done, but was there any issues?
checkAfterRun
exit

