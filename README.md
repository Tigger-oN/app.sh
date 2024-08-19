# app.sh

A helper script for working with the FreeBSD ports tree on the local machine.

	app.sh [abandoned | appvers | auto | distclean | old | pull | setup | work]
	app.sh command port1 [ port2... ]

command is required and must be one of the following:

    A | abandoned : Use result with caution. Check for out of date ports that 
                    *may not* be in use.
    a | auto      : Without confirmation, get the latest ports tree, then 
                    update any that are out of date.
    C | distclean : Remove the ports/distfiles data for the passed port(s) or 
                    all ports if no part is passed.
    h | help      : Show this help and exit.
    o | old       : List any out-of-date ports.
    p | pull      : Get the most recent version of the ports, then show which 
                    can be updated.
    S | setup     : Setup the local ports tree. Should only be needed once.
    V | appvers   : Show the script version and some basic information.
    W | work      : Look for any "work" subdirectories and clean them if 
                    found.

The following commands require at least one port name to be passed.

    b | build     : Configure (if needed) and build (but not install) the 
                    requested application(s).
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
                    For ports already installed. Reinstall / update the 
                    requested port(s).
    s | showconf  : Show the configuration options for a port only.

Port name is the "base name" of the port. You do not need to included the 
current version or the new version numbers. For example, to update vim to the 
latest version (assuming already installed):

    app.sh r vim


