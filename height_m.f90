module height_m
   implicit none
   real, private, allocatable, save, dimension(:) :: bet, betm

contains

subroutine initheight(nl,sig)

   use physparams

   integer, intent(in) :: nl
   real, intent(in), dimension(:) :: sig
   integer :: k
   real :: c

   ! MJT - Complete rewrite of this routine for compatability with CCAM
   
   allocate( bet(nl), betm(nl) )
   
   ! lapsbot=0 option from CCAM's indata.f
   do k=1,nl-1
      bet(k+1)=rdry*log(sig(k)/sig(k+1))*0.5
   end do
   c=grav/stdlapse
   bet(1)=c*(sig(1)**(-rdry/c)-1.)
   betm(:)=bet(:)
   
   return
end subroutine initheight

!-----------------------------------------------------------------
subroutine height ( tg, qg, zg, pg, sig, phistd, pstd )

!  Calculate geopotential height using virtual temperature
!  If the optional argument pstd is present it specifies the pressure levels
!  on which to calculate the height. Otherwise return sigma level heights.
   use physparams
   real, intent(in), dimension(:,:,:) :: tg, qg
   real, intent(in), dimension(:,:)   :: zg, pg
   real, intent(in), dimension(:)     :: sig
   real, intent(in), dimension(:), optional :: pstd
   real, intent(out), dimension(:,:,:) :: phistd

   real, dimension(size(tg,1),size(tg,3)) :: tv, phi
   integer :: j, k, lg, mg, kstd, ii
   real, dimension(size(tg,1)) :: siglev
   real :: bettemp, c

   integer :: nx, ny, nl, nstd

   nx = size(tg,1)
   ny = size(tg,2)
   nl = size(sig)

   if ( present ( pstd ) ) then
      nstd = size(pstd)
   else
      nstd = nl
   end if

   if ( nstd /= size(phistd,3) ) then
      print*, "Error, Incorrect size of array phistd in routine height"
      stop
   end if
   
   ! MJT - complete rewrite of this routine for compatibility with CCAM
   c=grav/stdlapse
   
   do lg=1,ny

!     Calculate virtual temperature.
      tv = tg(:,lg,:) * (epsil+qg(:,lg,:))/(epsil*(1.+qg(:,lg,:)))   
   
!     Calculate height on sigma levels
      phi(:,1) = zg(:,lg) * grav + bet(1)*tv(:,1)
      do k=2,nl
         phi(:,k) = phi(:,k-1)+bet(k)*tv(:,k)+betm(k)*tv(:,k-1)
      end do  
      
!     Now calculate the height at the standard pressure levels.
      if ( present ( pstd ) ) then
 
         do kstd = 1,nstd
            siglev = pstd(kstd)/pg(:,lg)
            do mg=1,nx
               if ( siglev(mg)>sig(1) ) then
                  bettemp=c*(siglev(mg)**(-rdry/c)-1.)
                  phistd(mg,lg,kstd) = zg(mg,lg)*grav+bettemp*tv(mg,1)
               else
                  ii = 1
                  do while ( siglev(mg)<sig(ii+1) .and. ii<nl-1 )
                     ii = ii+1
                  end do
                  bettemp=rdry*log(sig(ii)/siglev(mg))*0.5
                  phistd(mg,lg,kstd) = phi(mg,ii) + bettemp*(tv(mg,ii)+tv(mg,ii+1)) 
               end if
            end do
         end do

      else ! Return sigma level heights
         
         phistd(:,lg,:) = phi(:,:)

      end if
   end do       ! ny loop

   phistd = phistd / grav

end subroutine height

end module height_m
