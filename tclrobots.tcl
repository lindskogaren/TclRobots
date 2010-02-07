namespace import ::tcl::mathop::*
namespace import ::tcl::mathfunc::*

set ::tick 0

###############################################################################
#
# rand routine, scarffed from a comp.lang.tcl posting
#    From: eichin@cygnus.com (Mark Eichin)
#

set _lastvalue [expr ([pid]*[file atime /dev/tty])%65536]

proc _rawrand {} {
    global _lastvalue
    # per Knuth 3.6:
    # 65277 mod 8 = 5 (since 65536 is a power of 2)
    # c/m = .5-(1/6)\sqrt{3}
    # c = 0.21132*m = 13849, and should be odd.
    set _lastvalue [expr (65277*$_lastvalue+13849)%65536]
    set _lastvalue [expr ($_lastvalue+65536)%65536]
    return $_lastvalue
}
proc rand {base} {
    set rr [_rawrand]
    return [expr abs(($rr*$base)/65536)]
}


proc syscall {args} {
    set robot [lindex $args 0]
    set syscall [lrange $args 1 end]
    set result 0

    if {[lindex $syscall 0] eq "rand"} {
	set result [rand [lindex $syscall 1]]
    } else {
	set ::robotData($robot,syscall,$::tick) $syscall
    }
    puts -nonewline "syscall: "
    foreach arg $args {
	puts -nonewline "$arg "
    }
    puts ""

    return $result
}

proc init {} {
    set ::robots {r1}
    #set f [open robot1.tr]
    #set ::robotData(r1,code) [read $f]

    # Available data fields
    # ::robotData($robot,interp)
    # ::robotData($robot,reload)
    # ::robotData($robot,location)

    foreach robot $::robots {
	set ::robotData($robot,interp) [interp create -safe]

	set ::robotData($robot,reload) 0
	set ::robotData($robot,location) "[rand 999] [rand 999]"
	set ::robotData($robot,syscall,0) {}
	set ::robotData($robot,sysreturn,0) {}

	interp alias $::robotData($robot,interp) syscall {} syscall $robot

	$::robotData($robot,interp) invokehidden source syscalls.tcl

	#    $robotData($robot,interp) invokehidden source robot1.tr

	if {$robot eq "r1"} {
	    $::robotData($robot,interp) eval coroutine ${robot}Run {
		apply {
		    {} {
			set dir [rand 360]
			set nothing 0
			set closest 0
			while {1} {
			    set rng [scanner $dir 10]
			    dputs "rng: $rng"
			    if {$rng > 0 && $rng < 700} {
				set start [expr ($dir+20)%360]
				for {set limit 1} {$limit <= 40} {incr limit} {
				    set dir [expr ($start-($limit)+360)%360]
				    set rng [scanner $dir 1]
				    dputs "rng: $rng"
				    if {$rng > 0 && $rng < 700} {
					set nothing 0
					cannon $dir $rng
					drive $dir 70
					incr limit -4}}} else {
					    incr nothing
					    if {$rng > 700} {set closest $dir}}
			    drive 0 0
			    if {$nothing >= 30} {
				set nothing 0
				drive $closest 100
				after 10000 drive 0 0}
			    set dir [expr ($dir-20+360)%360]}
		    }
		}
	    }
	} elseif {$robot eq "r2"} {
	    $::robotData($robot,interp) eval coroutine ${robot}Run {
		apply {
		    {} {
			set corners {{10 10} {990 10} {10 990} {990 990}  }
			set cor_dir   {0       90       270      180}
			set dam [damage]
			proc I_was_scanned {who} {
			    dputs $who scanned me
			}
			alert I_was_scanned
			proc goto {x y} {
			    set rad2deg 57.2958
			    set hdg [expr int( $rad2deg * atan2(($y-[loc_y]),($x-[loc_x])) )]
			    if {$hdg < 0} {incr hdg 360}
			    drive $hdg 100
			    while { abs($x-[loc_x]) > 40 || abs($y-[loc_y]) > 40} {
				set hdg [expr int($rad2deg * atan2(($y-[loc_y]),($x-[loc_x])))]
				if {$hdg < 0} {incr hdg 360}
				if {[speed] <= 35} {
				    drive $hdg 100
				    global _debug
				    if {$_debug} {dputs hdg: $hdg to $x $y}
				}
			    }
			    drive $hdg 0
			}
			set x [loc_x]
			set y [loc_y]
			if {$x < 500} { set x 10; set s1 0 } else { set x 990; set s1 1 }
			if {$y < 500} { set y 10; set s2 0 } else { set y 990; set s2 1 }
			if { $s1 &&  $s2} { set start 180; set new_corner 3 }
			if { $s1 && !$s2} { set start  90; set new_corner 1 }
			if {!$s1 &&  $s2} { set start 270; set new_corner 2 }
			if {!$s1 && !$s2} { set start   0; set new_corner 0 }
			set resincr 5
			goto $x $y
			while {1} {
			    set num_scans 5
			    set dir $start
			    while { $num_scans > 0 && $dam+10 > [damage] } {
				set rng [scanner $dir $resincr]
				if {$rng >0 && $rng <= 700} {
				    set resincr 1
				    cannon $dir $rng
				    incr dir -8
				}
				incr dir $resincr
				if {$dir >= $start + 90} {
				    incr num_scans -1
				    set dir $start
				    set resincr 5
				}
			    }
			    set test_corner [rand 4]
			    while {$new_corner == $test_corner} {set test_corner [rand 4]}
			    set new_corner $test_corner
			    eval goto [lindex $corners $new_corner]
			    set start [lindex $cor_dir $new_corner]
			    set dam [damage]
			}
		    }
		}
	    }
	}

	interp alias {} ${robot}Run $::robotData($robot,interp) ${robot}Run

    }
}

proc sysScanner {robot} {
    if {($::tick > 0) &&
	($::robotData($robot,syscall,$::tick) eq \
	     $::robotData($robot,syscall,[- $::tick 1]))} {
	puts SCANNING
	set ::robotData($robot,sysreturn,$::tick) 500
    } else {
	puts scannerCharge
	set ::robotData($robot,sysreturn,$::tick) 600
    }
}

proc sysCannon {robot} {
    set ::robotData($robot,sysreturn,$::tick) 0
}

proc sysRand {robot} {
    rand [lindex $::robotData($robot,syscall,$::tick) 2]
}

proc sysDrive {robot} {
    set ::robotData($robot,drive) \
	[list [lindex $::robotData($robot,syscall,$::tick) 1] \
		   [lindex $::robotData($robot,syscall,$::tick) 2]]

    set ::robotData($robot,sysreturn,$::tick) $::robotData($robot,drive)

}

proc sysLoc_x {robot} {
    set ::robotData($robot,sysreturn,$::tick) \
	[lindex $::robotData($robot,location) 0]
}

proc sysLoc_y {robot} {
    set ::robotData($robot,sysreturn,$::tick) \
	[lindex $::robotData($robot,location) 1]
}

proc move {robot} {


    puts "$robot loc: $::robotData($robot,location)"
}

proc act {} {
    foreach robot $::robots {
	set currentSyscall $::robotData($robot,syscall,$::tick)
	puts "currentSyscall: $currentSyscall"
	switch [lindex $currentSyscall 0] {
	    scanner {sysScanner $robot}
	    cannon  {sysCannon  $robot}
	    drive   {sysDrive   $robot}
	    loc_x   {sysLoc_x   $robot}
	    loc_y   {sysLoc_y   $robot}
	}
	move $robot
    }
}

proc tick {} {
    incr ::tick
    puts "tick: $::tick\n"
}

proc main {} {
    init
    act
    tick

    for {set i 0} {$i < 20} {incr i} {
	foreach robot $::robots {
	    ${robot}Run $::robotData($robot,sysreturn,[- $::tick 1])
	}
	act
	tick
    }
}
main
