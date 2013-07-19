program cc2hist

!  This program generates a netcdf history file from the conformal-cubic
!  or conformal-octagon model output file. The interpolation routines are
!  taken from John's plotting program plotg.f.

!  It uses the f90 shallow water model versions of routines setxyz and staguv.

   use history
   use getopt_m
   use mpidata_m
   use newmpar_m
   use work
   use usage_m
   use height_m
   use s2p_m
   use interp_m
   use checkver_m
   use parm_m, only : rlong0, rlat0, schmidt

   implicit none

   include 'mpif.h'

   character(len=MAX_ARGLEN) :: ifile, ofile

   real :: hres = 0.
   real :: minlon = 0.0, maxlon=360.0, dlon=0.0, &
           minlat=-90.0, maxlat=90.0,  dlat=0.0

   character(len=MAX_ARGLEN) :: optarg
   integer :: opt, nopt
   type(loption), dimension(3) :: longopts
   integer :: longind
   integer :: kta=0, ktb=999999, ktc=-1, ndate=-1, ntime=-1, k
   integer :: sdate=-1, edate=-1, stime=-1, etime=-1
   character(len=10) :: name
   character(len=80) :: longname
   real :: minsig = 0., maxsig = 1.0
   logical :: darlam_grid = .false. ! depreciated !!!
   logical :: agrid = .true.        ! depreciated !!!

   namelist /input/ kta, ktb, ktc, ndate, ntime, &
                    minlon, maxlon, dlon, minlat, maxlat, dlat, &
                    minlev, maxlev, minsig, maxsig, use_plevs, plevs, &
                    sdate, edate, stime, etime, darlam_grid

   integer :: kt, kdate, ktime, ierr, ieof, ntracers
   logical :: all=.false., debug=.false.
   logical :: use_date, use_steps
   include 'revision.h'
   character(len=256) :: source, optionstring=""
   character(len=80)  :: basetime,calendar
   integer :: iyr, imon, iday, ihr, vid
   integer :: base_yr, base_mon, base_day, base_hr
   real :: time
   real, dimension(2) :: time_bnds
   logical :: skip
   type(input_var), dimension(:), pointer :: varlist
   integer :: nvars
   type(hist_att), dimension(:), allocatable :: extra_atts
   integer :: veg_int
   real :: time_prev = 0.

#ifndef stacklimit
   ! For linux only
   call setstacklimit(-1)
#endif

   call MPI_Init(ierr)
   call MPI_Comm_size(MPI_COMM_WORLD, nproc, ierr) ! Find number of processes
   call MPI_Comm_rank(MPI_COMM_WORLD, myid, ierr)  ! Find local processor id

!  Check versions of library modules.
   call checkver ( "history", history_revision, 7, 4 )

!  Get the command line options
   longopts(1) = loption ( "interp", 1, 0)
   longopts(2) = loption ( "vextrap", 1, 0 )
   longopts(3) = loption ( "cf", 0, 0 )
   ifile = ""
   ofile = ""
   do
      call getopt("adg:hi:o:r:t:v",nopt,opt,optarg,longopts,longind)
      if ( opt == -1 ) exit  ! End of options
      select case ( char(opt) )
      case ( "a" )
         all = .true.
      case ( "d" )
         debug = .true.
      case ( "g" ) 
         select case ( optarg )
         case ( "a" )
            agrid = .true.
         case ( "c" )
            agrid = .false.
         case  default
            if ( myid == 0 ) then
               print*, "Error: unknown grid type with -g "
            end if
            call usage()
         end select
      case ( "h" ) 
         call help(cc2hist_revision)
      case ( "i" ) 
         ifile = optarg
      case ( "o" ) 
         ofile = optarg
      case ( "r" ) 
         read(optarg,*) hres
      case ("v")
         if ( myid == 0 ) then
            print*, "cc2hist ", cc2hist_revision
         end if
      case ( char(0) )
         ! Long options that don't have a short form
         select case ( longind ) 
         case ( 1 ) 
            select case ( optarg )
            case ("nearest")
               int_default = int_nearest
               optionstring = optionstring(:len_trim(optionstring)) // " --interp=nearest"
            case ("linear")
               int_default = int_lin
               optionstring = optionstring(:len_trim(optionstring)) // " --interp=linear"
            case ( "none" )
               int_default = int_none
               optionstring = optionstring(:len_trim(optionstring)) // " --interp=none"
            case default
               print*, "Expected nearest, linear or none for interp option"
               stop
            end select
         case ( 2 )
            select case ( optarg )
            case ("linear")
               vextrap = vextrap_lin
            case ("none")
               vextrap = vextrap_none
               optionstring = optionstring(:len_trim(optionstring)) // " --vextrap=none"
            case ("missing")
               vextrap = vextrap_missing
               optionstring = optionstring(:len_trim(optionstring)) // " --vextrap=missing"
            case default
               print*, "Expected linear, none or missing for vextrap option"
               stop
            end select
         case ( 3 )
            cf_compliant = .true.
         case default
            print*, "Unexpected result processing long options", longind
            stop
         end select
      case default
         if ( myid == 0 ) then
            print*, "Error unknown option "
         end if
         call usage()
      end select
   end do

   if ( vextrap == vextrap_missing .and. int_default == int_normal ) then
      print*, "For missing option to work, must set interp to linear or nearest"
      stop
   end if

!  If filenames were not set as options look for them as arguments
   if ( len_trim(ifile) == 0 .and. len_trim(ofile) == 0 ) then
      if ( iargc() /= nopt+1 ) then
         if ( myid == 0 ) then
            print*, "Missing filenames"
         end if
         call usage()
      else
         call getarg(nopt,ifile)
         call getarg(nopt+1,ofile)
      end if
   end if

   if ( len_trim(ifile) == 0 .or. len_trim(ofile) == 0 ) then
      print*, "Error setting input/output filenames"
      stop
   end if

!  Only read the input namelist if the all flag hasn't been set.
!  This should be extended to allow specifying all pressure levels on the
!  command line too?
   if ( .not. all ) then
      if ( myid==0 ) then
         write(6,*) "reading cc.nml"
      end if
      open(1,file='cc.nml')
      read(1,input)
   end if
   if ( darlam_grid ) then
      print *,"Darlam is no longer supported"
      stop
   end if
   if ( .not. agrid ) then
      print *,"C-grid is no longer supported"
      stop
   end if
   

!  Check whether ndate and ntime have been set
   use_date = .false.
   if ( .not. ( sdate == -1 .and. edate == -1 .and. &
                stime == -1 .and. etime == -1 ) ) then
      use_date = .true.
   else if ( .not. ( ndate == -1 .and. ntime == -1 ) ) then
      use_date = .true.
      sdate = ndate
      edate = ndate
      stime = ntime
      etime = ntime
   end if
!  Set loop parameters to check all steps
   if ( use_date ) then
      kta=1
      ktb=huge(1)
      ktc=1
   end if
   if ( debug .and. use_date ) then
      print*, "Start", sdate, stime
      print*, "End  ", edate, etime
   end if

   use_steps = .not. use_date 

   call check_plevs
   
  
   call paraopen(ifile, NF90_NOWRITE, ncid)
   ! Check that this file wasn't produced by cc2hist itself
   call check_cc2histfile()

   call initialise ( hres,                                               &
                     minlon, maxlon, dlon, minlat, maxlat, dlat,         &
                     kdate, ktime, ntracers, ksoil, kice, debug,         &
                     nqg )
   call set_hbytes ( 4 )
   call set_htype ( "inst" )
   call set_hfreq ( 1 )

   minlev = max(1, minlev)
   maxlev = min(kl, maxlev)
!  Now find the index of the first sigma level above maxsig
   do k=minlev,maxlev
      if ( sig(k) <= maxsig ) exit
   end do
   minlev = k
!  Sigma level below minsig
   do k=maxlev,minlev,-1
      if ( sig(k) >= minsig ) exit
   end do
   maxlev = k
   nlev = maxlev - minlev + 1
   if ( nlev < 1 ) then
      print*, " Error: No vertical levels selected "
      print*, " Check minlev, maxlev, minsig, maxsig "
      stop
   end if
   if ( use_plevs) then
      nlev = nplevs
   end if

   call get_var_list(varlist,nvars)

   if ( all ) then
      call set_hnames("all")
   else
      call histnamelist(1)
      close(1)
   end if

!  openhist has to be called before any data is read because it allocates
!  the memory.
   if ( npanels == 5 ) then
      write(source,"(a,a,a,a)" ) "CSIRO conformal-cubic model. Input file: ",&
             trim(ifile), " Processed by cc2hist ", cc2hist_revision
   else
      write(source,"(a,a,a,a)" ) "CSIRO conformal-octagon model. Input file: ",& 
             trim(ifile), " Processed by cc2hist ", cc2hist_revision
   end if
   if ( len_trim(optionstring) /= 0 ) then
      source = trim(source) // " Options:" // trim(optionstring)
   end if

!     If the input is a netcdf file with a time:units attribute then copy that.
   ierr = nf90_inq_varid (ncid, "time", vid )
   call check_ncerr(ierr, "Error getting time id")
   basetime = ""
   ierr = nf90_get_att(ncid, vid, "units", basetime)
   call check_ncerr(ierr, "Error getting time:units attribute")
   calendar = ""
   ierr = nf90_get_att(ncid, vid, "calendar", calendar)

   if ( cf_compliant .and. basetime(1:13) == "minutes since" ) then
      basetime = "days" // basetime(8:len_trim(basetime))
   end if

   allocate ( extra_atts(5) )

   extra_atts(1:5) = (/ hist_att("il", NF90_INT, 0., il, ""),             &
                        hist_att("kl", NF90_INT, 0., kl, ""),             &
                        hist_att("rlong0", NF90_REAL, rlong0, 0, ""),     &
                        hist_att("rlat0", NF90_REAL, rlat0, 0, ""),       &
                        hist_att("schmidt", NF90_REAL, schmidt, 0, "") /)

   if ( calendar /= "" ) then
      if ( cf_compliant ) then
         if ( use_plevs ) then
            call openhist( il, jl, nlev, plevs(1:nplevs), "_test", hlon, hlat,    &
                           basetime, year=1, nxout=nxhis, nyout=nyhis,            &
                           source=source, histfilename=ofile, pressure=use_plevs, &
                           extra_atts=extra_atts, nsoil=ksoil, zsoil=zsoil,       &
                           calendar=calendar )
         else
            call openhist( il, jl, nlev, sig(minlev:maxlev), "_test", hlon, hlat, &
                          basetime, year=1, nxout=nxhis, nyout=nyhis,             &
                          source=source, histfilename=ofile,                      &
                          extra_atts=extra_atts, nsoil=ksoil, zsoil=zsoil,        &
                          calendar=calendar )
         end if
      else
         if ( use_plevs ) then
            call openhist ( il, jl, nlev, plevs(1:nplevs), "_test", hlon, hlat,    &
                            basetime, year=1, nxout=nxhis, nyout=nyhis,            &
                            source=source, histfilename=ofile, pressure=use_plevs, &
                            extra_atts=extra_atts, calendar=calendar )
         else
            call openhist ( il, jl, nlev, sig(minlev:maxlev), "_test", hlon, hlat,    &
                            basetime, year=1, nxout=nxhis, nyout=nyhis,               &
                            source=source, histfilename=ofile, extra_atts=extra_atts, &
                            calendar=calendar )
         end if
      end if
   else
       if ( cf_compliant ) then
         if ( use_plevs ) then
            call openhist( il, jl, nlev, plevs(1:nplevs), "_test", hlon, hlat,    &
                           basetime, year=1, nxout=nxhis, nyout=nyhis,            &
                           source=source, histfilename=ofile, pressure=use_plevs, &
                           extra_atts=extra_atts, nsoil=ksoil, zsoil=zsoil )
         else
            call openhist( il, jl, nlev, sig(minlev:maxlev), "_test", hlon, hlat, &
                          basetime, year=1, nxout=nxhis, nyout=nyhis,             &
                          source=source, histfilename=ofile,                      &
                          extra_atts=extra_atts, nsoil=ksoil, zsoil=zsoil )
         end if
      else
         if ( use_plevs ) then
            call openhist ( il, jl, nlev, plevs(1:nplevs), "_test", hlon, hlat,    &
                            basetime, year=1, nxout=nxhis, nyout=nyhis,            &
                            source=source, histfilename=ofile, pressure=use_plevs, &
                            extra_atts=extra_atts )
         else
            call openhist ( il, jl, nlev, sig(minlev:maxlev), "_test", hlon, hlat,     &
                            basetime, year=1, nxout=nxhis, nyout=nyhis,                &
                            source=source, histfilename=ofile, extra_atts=extra_atts )
         end if
      end if  
   end if

!  needfld calls are only valid after openhist
   call final_init(varlist,nvars)

   if (needfld("zg")) then
      call initheight(kl,sig)
   end if

!  If ktc is still -1 and ndate and ntime aren't set then process all fields
   if ( ktc == -1 ) then
      ktc = 1
      if ( .not. use_date ) then
         all = .true.
      end if
   end if

   timeloop: do kt=kta,ktb,ktc
      if ( debug ) then
         print*, "KT", kt
      end if
      do ! Loop through until time found
         call getdate ( kdate, ktime, ieof )
         if ( ieof /= 0 ) then  ! END OF FILE
            exit timeloop
         end if
         if ( debug ) then
            print*, "KTAU, KT", ktau, kt
         end if
         
         if  ( all ) then ! Date/time doesn't matter
            if ( debug ) then
               print*, " Saving (all) "
            end if
            skip = .false.
         else if ( use_steps ) then
!           Check whether the correct time has been found
            if ( ktau < kt ) then
               skip = .true.
            else if ( ktau == kt ) then
               if ( debug ) then
                  print*, " Saving (ktau=kt) "
               end if
               skip = .false.
            end if

!        Check for matching date and time
         else if ( use_date ) then
!           Check if reached startdate
            if ( kdate < sdate .or. &
                 ( kdate == sdate .and. ktime < stime ) ) then
               if ( debug ) then
                  print*, " before start date"
               end if
!              Go to next timeloop iteration, so kt advances.
               skip = .true. 
!           Check if past enddate
            else if ( kdate > edate .or. &
                      ( kdate == edate .and. ktime > etime ) ) then
               if ( debug ) then
                  print*, " past end date"
               end if
!              Finished
               exit timeloop
            else
               if ( debug ) then
                  print*, " Saving (ndate, ntime) "
               end if
               skip = .false. 
               exit
            end if
         end if

         if ( myid == 0 ) then
            if ( kt < ktau ) then
               print*, "WARNING: Searching for step", kt
            end if
         end if

         call infile(varlist, nvars, skip)

         if ( myid == 0 ) then
            if ( skip ) then
               write(*,"(a)") " - Skipped"
            else
               write(*,"(a)") " - Saved"
            end if
         end if

         if ( .not. skip ) then
            exit
         end if
         if ( use_date ) then
!           Go to next timeloop iteration, so kt advances.
            cycle timeloop
         end if

      end do

      if ( skip ) then
         cycle
      end if

!     Time in hours
      if  ( use_steps ) then
         time=real(ktau)
      else
         iyr = kdate/10000
         imon = modulo(kdate,10000) / 100
         iday = modulo(kdate,100)
         ihr = ktime/100
!        Need to extend to work over more than one month.
         time = (iday - base_day)*24 + ihr-base_hr
      end if
      if ( cf_compliant ) then 
         time = time/1440. ! Days
         ! History data at time t, really represents values over the preceeding
         ! period in the case of accumulated or average fields.
         ! Should this be the history file time increment or the increment
         ! set for cc2hist?
         time_bnds = (/time_prev,time/)
         call writehist ( ktau, interp=ints, time=time, time_bnds=time_bnds )
         time_prev = time
      else
         call writehist ( ktau, interp=ints, time=time)
      end if

   end do timeloop

   call writehist(ktau, interp=ints, time=time, endofrun=.true. )
   if ( myid == 0 ) then
      call closehist
   end if
   call paraclose

   call MPI_Finalize(ierr)

end program cc2hist
