!--------------------------------------------------------------------------------------------------!
!  DFTB+: general package for performing fast atomistic simulations                                !
!  Copyright (C) 2006 - 2022  DFTB+ developers group                                               !
!                                                                                                  !
!  See the LICENSE file for terms of usage and distribution.                                       !
!--------------------------------------------------------------------------------------------------!

#:include 'common.fypp'

!> Module containing routines for numerical second derivs of energy using central finite difference.
!> To Do: Option to restart the calculation
module dftbp_derivs_numderivs2
  use dftbp_common_accuracy, only : dp
  implicit none

  private
  public :: TNumDerivs, create, next, getHessianMatrix


  !> Contains necessary data for the derivs
  type :: TNumDerivs
    private

    !> Internal matrix to hold derivative and intermediate values for their construction
    !>
    !> Must be pointer, so that the type can safely return a pointer to it.
    !>
    real(dp), pointer :: derivs(:,:) => null()

    !> Coordinates at x=0 to differentiate at
    real(dp), allocatable :: x0(:,:)

    !> How many derivates are moved
    integer :: nMovedAtoms

    !> Which atom are we currently differentiating with respect to?
    integer :: iAtom

    !> Which component, x,y,z are we currently differentiating with respect to?
    integer :: iComponent

    !> displacement along + or - for central difference
    real(dp) :: iDelta

    !> Step size for derivative
    real(dp) :: delta

  contains

    final :: TNumDerivs_final

  end type TNumDerivs


  !> Create numerical second derivatives instance
  interface create
    module procedure derivs_create
  end interface


  !> Delivers the next set of coordinates for evaluation of forces
  interface next
    module procedure derivs_next
  end interface


  !> Get the Hessian matrix of derivatives for the system
  interface getHessianMatrix
    module procedure getDerivMatrixPtr
  end interface

contains


  !> Create new instance of derivative object
  !> Note: Use pre-relaxed coordinates when starting this, as the truncation at second
  !> derivatives is only valid at the minimum position.
  !> The subroutine can allocate a rectangular matrix with parameter nDerivAtoms,
  !> Useful for distributed calculations of the Hessian
  subroutine derivs_create(this, xInit, nDerivAtoms, delta)

    !> Pointer to the initialised object on exit.
    type(TNumDerivs), allocatable, intent(out) :: this

    !> initial atomic coordinates (3, nMovedAtom)
    real(dp), intent(inout) :: xInit(:,:)

    !> number of atoms for which derivatives should be calculated (>= nMovedAtom)
    integer, intent(in) :: nDerivAtoms

    !> step size for numerical derivative
    real(dp), intent(in) :: delta

    integer :: nMovedAtoms

    @:ASSERT(size(xInit,dim=1)==3)
    nMovedAtoms = size(xInit,dim=2)

    allocate(this)
    allocate(this%x0(3, nMovedAtoms))
    this%x0(:,:) = xInit(:,:)
    allocate(this%derivs(3 * nDerivAtoms, 3 * nMovedAtoms), source=0.0_dp)
    this%nMovedAtoms = nMovedAtoms
    this%delta = delta

    this%iAtom = 1
    this%iComponent = 1
    this%iDelta = -1.0_dp

    xInit(this%iComponent,this%iAtom) = &
        & xInit(this%iComponent,this%iAtom) + this%iDelta*this%delta

  end subroutine derivs_create


  !> Takes the next step for derivatives using the central difference formula to choose the new
  !> coordinates for differentiation of the forces with respect to atomic coordinates
  subroutine derivs_next(this,xNew,fOld,tGeomEnd)

    !> Derivatives instance to propagate
    type(TNumDerivs), intent(inout) :: this

    !> New coordinates for the next step
    real(dp), intent(out) :: xNew(:,:)

    !> Forces for the previous geometry
    real(dp), intent(in) :: fOld(:,:)

    !> Has the process terminated? If so internally calculate the Hessian matrix.
    logical, intent(out) :: tGeomEnd

    integer :: ii, jj, nDerivAtoms

    @:ASSERT(all(shape(xNew)==(/3,this%nMovedAtoms/)))
    nDerivAtoms = size(this%derivs, dim=1)/3
    @:ASSERT(size(fOld,1)==3)
    @:ASSERT(size(fOld,2)==nDerivAtoms)

    tGeomEnd = (this%iAtom == this%nMovedAtoms .and. this%iComponent == 3&
        & .and. this%iDelta > 0.0_dp)

    do ii = 1, nDerivAtoms
      do jj = 1, 3
        this%derivs((ii-1)*3+jj,(this%iAtom-1)*3+this%iComponent) = &
            & this%derivs((ii-1)*3+jj,(this%iAtom-1)*3+this%iComponent) &
            & + this%iDelta * fOld(jj,ii)
      end do
    end do

    if (.not.tGeomEnd) then

      if (this%iDelta < 0.0_dp) then
        this%iDelta = 1.0_dp
      else
        this%iDelta = -1.0_dp
        if (this%iComponent == 3) this%iAtom = this%iAtom + 1
        this%iComponent = mod(this%iComponent,3) + 1
      end if

      xNew(:,:) = this%x0(:,:)
      xNew(this%iComponent,this%iAtom) = xNew(this%iComponent,this%iAtom) + &
          & this%iDelta * this%delta
    else
      ! get actual derivatives
      this%derivs(:,:) = 0.5_dp*this%derivs(:,:)/(this%delta)
      ! set xnew to an arbitrary value
      xNew(:,:) = this%x0
    end if

  end subroutine derivs_next


  !> Routine to return pointer to internal matrix of derivative elements.
  subroutine getDerivMatrixPtr(this,d)

    !> Derivatives instance including the Hessian internally
    type(TNumDerivs), intent(in) :: this

    !> Pointer to the Hessian matrix to allow retrieval
    real(dp), pointer, intent(out) :: d(:,:)

    d => this%derivs

  end subroutine getDerivMatrixPtr


  !> Finalizes TNumDerivs instance.
  subroutine TNumDerivs_final(this)

    !> Instance
    type(TNumDerivs), intent(inout) :: this

    if (associated(this%derivs)) deallocate(this%derivs)

  end subroutine TNumDerivs_final

end module dftbp_derivs_numderivs2
