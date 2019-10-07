+++
title = "Recipe: Obtaining Peak VM Size in Pure Fortran"
date = 2014-05-22T12:34:30
draft = false
highlight_languages = ["fortran"]
tags = ["recipes", "hpc", "fortran", "linux"]
categories = []

# Featured image
# Place your image in the `static/img/` folder and reference its filename below, e.g. `image = "example.jpg"`.
[header]
image = ""
caption = ""
+++

Often in High Performance Computing one needs to know about the various memory metrics of a given program with the peak memory usage probably being the most important one.
While the `getrusage(2)` syscall provides some of that information, it's use in Fortran programs is far from optimal and there are lots of metrics that are not exposed by it.

On Linux one could simply parse the `/proc/PID/status` file.
Being a simple text file it could easily be processed entirely with the built-in Fortran machinery as shown in the following recipe:

``` fortran
program test
  integer :: vmpeak

  call get_vmpeak(vmpeak)
  print *, 'Peak VM size: ', vmpeak, ' kB'
end program test

!---------------------------------------------------------------!
! Returns current process' peak virtual memory size             !
! Requires Linux procfs mounted at /proc                        !
!---------------------------------------------------------------!
! Output: peak - peak VM size in kB                             !
!---------------------------------------------------------------!
subroutine get_vmpeak(peak)
  implicit none
  integer, intent(out) :: peak
  character(len=80) :: stat_key, stat_value
  !
  peak = 0
  open(unit=1000, name='/proc/self/status', status='old', err=99)
  do while (.true.)
    read(unit=1000, fmt=*, err=88) stat_key, stat_value
    if (stat_key == 'VmPeak:') then
      read(unit=stat_value, fmt='(I)') peak
      exit
    end if
  end do
88 close(unit=1000)
  if (peak == 0) goto 99
  return
  !
99 print *, 'ERROR: procfs not mounted or not compatible'
  peak = -1
end subroutine get_vmpeak
```

The code accesses the status file of the calling process `/proc/self/status`.
The unit number is hard-coded which could present problems in some cases.
Modern Fortran 2008 compilers support the `NEWUNIT` specifier and the following code could be used instead:

``` fortran
integer :: unitno 

open(newunit=unitno, name='/proc/self/status', status='old', err=99)
! ...
close(unit=unitno)
```

With older compilers the same functionality could be simulated using the [following code](http://fortranwiki.org/fortran/show/newunit).
