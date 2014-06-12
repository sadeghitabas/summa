module phseChange_module
USE nrtype
! physical constants
USE multiconst,only:&
                    Tfreeze,     & ! freezing point of pure water  (K)
                    iden_air,    & ! intrinsic density of air      (kg m-3)
                    iden_ice,    & ! intrinsic density of ice      (kg m-3)
                    iden_water,  & ! intrinsic density of water    (kg m-3)
                    gravity,     & ! gravitational acceleteration  (m s-2)
                    LH_fus         ! latent heat of fusion         (J kg-1)
implicit none
private
public::phseChange
contains

 ! ************************************************************************************************
 ! new subroutine: compute phase change impacts on matric head and volumetric liquid water and ice
 ! ************************************************************************************************
 subroutine phseChange(&
                       ! input
                       mLayerTempNew,       & ! intent(in): new temperature vector (K)
                       mLayerMatricHeadIter,& ! intent(in): matric head at the current iteration (m)
                       mLayerVolFracLiqIter,& ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                       mLayerVolFracIceIter,& ! intent(in): volumetric fraction of ice at the current iteration (-)
                       ! output
                       mLayerMatricHeadNew, & ! intent(out): new matric head (m)
                       mLayerVolFracLiqNew, & ! intent(out): new volumetric fraction of liquid water (-)
                       mLayerVolFracIceNew, & ! intent(out): new volumetric fraction of ice (-)
                       err,message)           ! intent(out): error control
 ! utility routines
 USE snow_utils_module,only:fracliquid    ! compute volumetric fraction of liquid water
 USE soil_utils_module,only:volFracLiq    ! compute volumetric fraction of liquid water based on matric head
 USE soil_utils_module,only:matricHead    ! compute the matric head based on volumetric liquid water content
 ! data structures
 USE data_struc,only:mpar_data,mvar_data,indx_data,ix_soil,ix_snow    ! data structures
 USE var_lookup,only:iLookPARAM,iLookMVAR,iLookINDEX                  ! named variables for structure elements
 implicit none
 ! input variables
 real(dp),intent(in)           :: mLayerTempNew(:)         ! new estimate of temperature (K)
 real(dp),intent(in)           :: mLayerMatricHeadIter(:)  ! before phase change: matric head (m)
 real(dp),intent(in)           :: mLayerVolFracLiqIter(:)  ! before phase change: volumetric fraction of liquid water (-)
 real(dp),intent(in)           :: mLayerVolFracIceIter(:)  ! before phase change: volumetric fraction of ice (-)
 ! output variables
 real(dp),intent(out)          :: mLayerMatricHeadNew(:)   ! after phase change: matric head (m)
 real(dp),intent(out)          :: mLayerVolFracLiqNew(:)   ! after phase change: volumetric fraction of liquid water (-)
 real(dp),intent(out)          :: mLayerVolFracIceNew(:)   ! after phase change: volumetric fraction of ice (-)
 integer(i4b),intent(out)      :: err                      ! error code
 character(*),intent(out)      :: message                  ! error message
 ! local pointers to model parameters
 real(dp),pointer              :: snowfrz_scale            ! scaling parameter for the snow freezing curve (K-1)
 real(dp),pointer              :: vGn_alpha                ! van Genutchen "alpha" parameter
 real(dp),pointer              :: vGn_n                    ! van Genutchen "n" parameter
 real(dp),pointer              :: theta_sat                ! soil porosity (-)
 real(dp),pointer              :: theta_res                ! soil residual volumetric water content (-)
 real(dp),pointer              :: vGn_m                    ! van Genutchen "m" parameter (-)
 real(dp),pointer              :: kappa                    ! constant in the freezing curve function (m K-1)
 ! local pointers to model variables
 integer(i4b),pointer          :: layerType(:)             ! type of the layer (ix_soil or ix_snow)
 ! define local variables
 real(dp)                      :: fLiq                     ! fraction of liquid water (-)
 real(dp)                      :: theta                    ! liquid water equivalent of total water (-)
 real(dp)                      :: vTheta                   ! fractional volume of total water (-)
 real(dp)                      :: xPsi00                   ! matric head when all water is unfrozen (m)
 real(dp)                      :: TcSoil                   ! critical soil temperature when all water is unfrozen (K)
 integer(i4b)                  :: nSnow                    ! number of snow layers
 integer(i4b)                  :: iLayer                   ! index of model layer
 logical(lgt)                  :: printflag                ! flag to print debug information
 ! initialize error control
 err=0; message="phsechange/"

 ! initialize print flag
 printflag=.false.

 ! assign pointers to model parameters
 snowfrz_scale    => mpar_data%var(iLookPARAM%snowfrz_scale)        ! scaling parameter for the snow freezing curve (K-1)
 vGn_alpha        => mpar_data%var(iLookPARAM%vGn_alpha)            ! van Genutchen "alpha" parameter (m-1)
 vGn_n            => mpar_data%var(iLookPARAM%vGn_n)                ! van Genutchen "n" parameter (-)
 theta_sat        => mpar_data%var(iLookPARAM%theta_sat)            ! soil porosity (-)
 theta_res        => mpar_data%var(iLookPARAM%theta_res)            ! soil residual volumetric water content (-)
 vGn_m            => mvar_data%var(iLookMVAR%scalarVGn_m)%dat(1)    ! van Genutchen "m" parameter (-)
 kappa            => mvar_data%var(iLookMVAR%scalarKappa)%dat(1)    ! constant in the freezing curve function (m K-1)

 ! assign pointers to index variables
 layerType        => indx_data%var(iLookINDEX%layerType)%dat        ! layer type (ix_soil or ix_snow)

 ! identify the number of snow layers
 nSnow = count(layerType==ix_snow)

 ! update volumetric liquid and ice content (-)
 do iLayer=1,size(layerType)  ! (process snow and soil separately)

  select case(layerType(iLayer))

   ! ** snow
   case(ix_snow)
    ! compute liquid water equivalent of total water (liquid plus ice)
    theta = mLayerVolFracIceIter(iLayer)*(iden_ice/iden_water) + mLayerVolFracLiqIter(iLayer)
    ! compute the volumetric fraction of liquid water and ice (-)
    fLiq = fracliquid(mLayerTempNew(iLayer),snowfrz_scale)
    mLayerVolFracLiqNew(iLayer) = fLiq
    mLayerVolFracIceNew(iLayer) = (1._dp - fLiq)*theta*(iden_water/iden_ice)
    write(*,'(a,1x,i4,1x,4(f20.10,1x))') 'in phase change: iLayer, fLiq, theta, mLayerVolFracIceNew(iLayer) = ', &
                                                           iLayer, fLiq, theta, mLayerVolFracIceNew(iLayer)

   ! ** soil
   case(ix_soil)
    ! compute fractional **volume** of total water (liquid plus ice)
    vTheta = mLayerVolFracLiqIter(iLayer) + mLayerVolFracIceIter(iLayer)
    if(vTheta > theta_sat)then; err=20; message=trim(message)//'volume of liquid and ice exceeds porisity'; return; endif
    ! compute the matric potential corresponding to the total liquid water and ice (m)
    xPsi00 = matricHead(vTheta,vGn_alpha,theta_res,theta_sat,vGn_n,vGn_m)
    ! compute the critical soil temperature where all water is unfrozen (K)
    TcSoil = Tfreeze + xPsi00*gravity*Tfreeze/LH_fus  ! (NOTE: J = kg m2 s-2, so LH_fus is in units of m2 s-2)
    ! update state variables
    if(mLayerTempNew(iLayer) < TcSoil)then ! (check if soil temperature is less than the critical temperature)
     ! compute matric head and volumetric fraction of liquid water
     ! NOTE: these variables are not strictly needed for the phase change calculations
     !         -- However, they provide a useful first guess in the hydrology calculations later
     mLayerMatricHeadNew(iLayer-nSnow) = xPsi00 + (LH_fus/(gravity*TcSoil))*(mLayerTempNew(iLayer) - TcSoil)
     mLayerVolFracLiqNew(iLayer)       = volFracLiq(mLayerMatricHeadNew(iLayer),vGn_alpha,theta_res,theta_sat,vGn_n,vGn_m)
     ! compute phase change
     mLayerVolFracIceNew(iLayer)       = vTheta - mLayerVolFracLiqNew(iLayer)
     if(iLayer==1)&
     write(*,'(a,1x,10(e20.10,1x))') 'in phseChange: mLayerMatricHeadNew(iLayer-nSnow), vTheta, xPsi00 = ', &
                                                     mLayerMatricHeadNew(iLayer-nSnow), vTheta, xPsi00
    ! case where all water is unfrozen
    else
     ! update volumetric liquid water and ice content
     mLayerVolFracLiqNew(iLayer) = vTheta
     mLayerVolFracIceNew(iLayer) = 0._dp
     ! take matric head from the previous iteration (could be saturated)
     mLayerMatricHeadNew(iLayer-nSnow) = mLayerMatricHeadIter(iLayer)
    endif  ! (soil temperature less than critical temperature)

   ! ** check errors
   case default; err=10; message=trim(message)//'unknown case for model layer'; return

  endselect

  ! print results
  !if(iLayer > nSnow .and. iLayer < nSnow+3) &
  ! write(*,'(a,i4,1x,10(f20.10,1x))') 'in phase change: temp, liquid (iter), ice (iter, new, diff)', &
  !  iLayer, mLayerTempNew(iLayer), mLayerVolFracLiqIter(iLayer), mLayerVolFracIceIter(iLayer), mLayerVolFracIceNew(iLayer), &
  !  mLayerVolFracIceNew(iLayer) - mLayerVolFracIceIter(iLayer)


  ! sanity check
  if(mLayerVolFracIceNew(iLayer) < -tiny(theta_sat))then
   write(message,'(a,i0,a,e20.10,a)')trim(message)//"volumetric ice content < 0 [iLayer=",iLayer,&
                                     &"; mLayerVolFracIceNew(iLayer)=",mLayerVolFracIceNew(iLayer),"]"
   err=10; return
  endif

 end do ! (looping through layers)
 endsubroutine phseChange

end module phseChange_module
