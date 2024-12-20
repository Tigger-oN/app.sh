# app.sh

A helper script for working with the FreeBSD ports tree on the local machine.

	app.sh [abandoned | auto | distclean | fetchindex | old | pull | setup 
            | version | work]
	app.sh command port1 [port2...]

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
    W | work      : Look for any "work" subdirectories and clean them if found.
                    This is a best guess process.

The following commands require at least one port name to be passed.

    b | build     : Configure (if needed) and build but not install the requested
                    application(s).
    c | config    : Set configuration options for a port only.
    d | rm | del | delete | remove :
                    (Recommended) Delete the requested port(s) using
                    "pkg delete <port>". Will remove all related port(s). A
                    confirmation is required.
    D | deinstall : Use "make deinstall" in the port tree directory. Only the
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

Port name is the "base name" of the port. Do not included the current version
or the new version numbers. For example, to update vim to the latest version 
(assuming already installed):

    app.sh r vim

Reinstall and Update (capital R/U) will search for and list all ports based on
a matched part of a port name. Helpful for updating a group of ports without
the need to type the entire list. Reinstall will search the installed list of
ports. Update will only look at superseded ports. You can search on more than
one term.


