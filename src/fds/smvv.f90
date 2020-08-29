MODULE ISOSMOKE
  USE PRECISION_PARAMETERS
 ! USE GLOBAL_CONSTANTS  ! needed if write(LU_ERR,*) debug statements are present
  USE MEMORY_FUNCTIONS, ONLY: ChkMemErr

  IMPLICIT NONE

  CHARACTER(255), PARAMETER :: smvvid='$Id: smvv.f90 19852 2014-07-07 01:52:02Z gforney $'
  CHARACTER(255), PARAMETER :: smvvrev='$Revision: 19852 $'
  CHARACTER(255), PARAMETER :: smvvdate='$Date: 2014-07-06 18:52:02 -0700 (Sun, 06 Jul 2014) $'

  PRIVATE
  PUBLIC ISO_TO_FILE,SMOKE3D_TO_FILE,GET_REV_smvv

CONTAINS

! ------------------ GET_REV_smvv ------------------------

SUBROUTINE GET_REV_smvv(MODULE_REV,MODULE_DATE)
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE

WRITE(MODULE_DATE,'(A)') smvvrev(INDEX(smvvrev,':')+2:LEN_TRIM(smvvrev)-2)
READ (MODULE_DATE,'(I5)') MODULE_REV
WRITE(MODULE_DATE,'(A)') smvvdate

END SUBROUTINE GET_REV_smvv

! ------------------ ISO_TO_FILE ------------------------

SUBROUTINE ISO_TO_FILE(LU_ISO,T,VDATA,&
           LEVELS, NLEVELS, IBLANK, XPLT, NX, YPLT, NY, ZPLT, NZ)
  
  INTEGER, INTENT(IN) :: NX, NY, NZ
  INTEGER, INTENT(INOUT) :: LU_ISO
  REAL(FB), INTENT(IN) :: T
  REAL(FB), INTENT(IN), DIMENSION(0:NX,0:NY,0:NZ) :: VDATA
  INTEGER, INTENT(IN), DIMENSION(NX-1,NY-1,NZ-1) :: IBLANK
  INTEGER, INTENT(IN) :: NLEVELS
  REAL(FB), INTENT(IN), DIMENSION(NLEVELS) :: LEVELS
  REAL(FB), INTENT(IN), DIMENSION(NX) :: XPLT
  REAL(FB), INTENT(IN), DIMENSION(NY) :: YPLT
  REAL(FB), INTENT(IN), DIMENSION(NZ) :: ZPLT
           
  INTEGER :: I
  INTEGER :: NXYZVERTS, NTRIANGLES, NXYZVERTS_ALL, NTRIANGLES_ALL
  REAL(FB), DIMENSION(:), POINTER :: XYZVERTS
  INTEGER, DIMENSION(:), POINTER :: TRIANGLES, LEVEL_INDICES
  REAL(FB), DIMENSION(:), POINTER :: XYZVERTS_ALL
  INTEGER, DIMENSION(:), POINTER :: TRIANGLES_ALL, LEVEL_INDICES_ALL
  INTEGER :: MEMERR
  
  NXYZVERTS_ALL=0
  NTRIANGLES_ALL=0
  
  NULLIFY(XYZVERTS)
  NULLIFY(TRIANGLES)
  NULLIFY(LEVEL_INDICES)
  
  NULLIFY(XYZVERTS_ALL)
  NULLIFY(TRIANGLES_ALL)
  NULLIFY(LEVEL_INDICES_ALL)

  DO I =1, NLEVELS
    CALL ISO_TO_GEOM(VDATA, LEVELS(I), &
          IBLANK, XPLT, NX, YPLT, NY, ZPLT, NZ,XYZVERTS, NXYZVERTS, TRIANGLES, NTRIANGLES)
    IF (NTRIANGLES>0.AND.NXYZVERTS>0) THEN
      ALLOCATE(LEVEL_INDICES(NTRIANGLES),STAT=MEMERR)
      CALL ChkMemErr('ISO_TO_FILE','LEVEL_INDICES',MEMERR)
      LEVEL_INDICES=I
      CALL MERGE_GEOM(TRIANGLES_ALL,LEVEL_INDICES_ALL,NTRIANGLES_ALL,XYZVERTS_ALL,NXYZVERTS_ALL,&
           TRIANGLES,LEVEL_INDICES,NTRIANGLES,XYZVERTS,NXYZVERTS)
      DEALLOCATE(LEVEL_INDICES)
      DEALLOCATE(XYZVERTS) ! these variables were allocated in ISO_TO_GEOM
      DEALLOCATE(TRIANGLES)
    ENDIF
  END DO
  IF (NXYZVERTS_ALL>0.AND.NTRIANGLES_ALL>0) THEN
    CALL REMOVE_DUPLICATE_ISO_VERTS(XYZVERTS_ALL,NXYZVERTS_ALL,TRIANGLES_ALL,NTRIANGLES_ALL)
  ENDIF
  IF (LU_ISO<0) THEN
    LU_ISO  = ABS(LU_ISO)
    CALL ISO_HEADER_OUT(LU_ISO,LEVELS,NLEVELS)
  ENDIF
  CALL ISO_OUT(LU_ISO,T,XYZVERTS_ALL,NXYZVERTS_ALL,TRIANGLES_ALL,LEVEL_INDICES_ALL,NTRIANGLES_ALL)
  IF (NXYZVERTS_ALL>0.AND.NTRIANGLES>0) THEN
    DEALLOCATE(XYZVERTS_ALL)
    DEALLOCATE(LEVEL_INDICES_ALL)
    DEALLOCATE(TRIANGLES_ALL)
  ENDIF

  RETURN
END SUBROUTINE ISO_TO_FILE

! ------------------ COMPARE_VEC3 ------------------------

INTEGER FUNCTION COMPARE_VEC3(XI,XJ)
REAL(FB), INTENT(IN), DIMENSION(3) :: XI, XJ

REAL(FB) :: DELTA=0.01_FB

IF (XI(1)<XJ(1)-DELTA) THEN
  COMPARE_VEC3 = -1
  RETURN
ENDIF
IF (XI(1)>XJ(1)+DELTA) THEN
  COMPARE_VEC3 = 1
  RETURN
ENDIF
IF (XI(2)<XJ(2)-DELTA) THEN
  COMPARE_VEC3 = -1
  RETURN
ENDIF
IF (XI(2)>XJ(2)+DELTA) THEN
  COMPARE_VEC3 = 1
  RETURN
ENDIF
IF (XI(3)<XJ(3)-DELTA) THEN
  COMPARE_VEC3 = -1
  RETURN
ENDIF
IF (XI(3)>XJ(3)+DELTA) THEN
  COMPARE_VEC3 = 1
  RETURN
ENDIF
COMPARE_VEC3 = 0
RETURN
END FUNCTION COMPARE_VEC3

! ------------------ GET_MATCH ------------------------

INTEGER FUNCTION GET_MATCH(XYZ,VERTS,NVERTS)

  INTEGER, INTENT(IN) :: NVERTS
  REAL(FB), INTENT(IN), DIMENSION(3) :: XYZ
  REAL(FB), INTENT(IN), DIMENSION(3*NVERTS) :: VERTS
  
  REAL(FB), DIMENSION(3) :: XYZI
  INTEGER :: I

  DO I = 1, NVERTS
    XYZI = VERTS(3*I-2:3*I)
    IF (COMPARE_VEC3(XYZ,XYZI)==0) THEN
      GET_MATCH=I
      RETURN
    ENDIF
  END DO
  GET_MATCH=0
END FUNCTION GET_MATCH

! ------------------ REMOVE_DUPLICATE_ISO_VERTS ------------------------

SUBROUTINE REMOVE_DUPLICATE_ISO_VERTS(VERTS,NVERTS,TRIANGLES,NTRIANGLES)

REAL(FB), INTENT(INOUT), POINTER, DIMENSION(:)  :: VERTS
INTEGER, INTENT(INOUT), POINTER, DIMENSION(:) :: TRIANGLES
INTEGER, INTENT(IN) :: NTRIANGLES
INTEGER, INTENT(INOUT) :: NVERTS 

INTEGER, ALLOCATABLE, DIMENSION(:) :: MAPVERTS
INTEGER :: I,NVERTS_OLD,IFROM,ITO
INTEGER :: MEMERR
REAL(FB), DIMENSION(3) :: XYZFROM
INTEGER :: IMATCH

NVERTS_OLD = NVERTS

IF (NVERTS==0.OR.NTRIANGLES==0)RETURN
ALLOCATE(MAPVERTS(NVERTS),STAT=MEMERR)
CALL ChkMemErr('REMOVE_DUPLICATE_VERTS','MAPVERTS',MEMERR)

MAPVERTS(1)=1
ITO=2
DO IFROM=2, NVERTS
  XYZFROM(1:3) = VERTS(3*IFROM-2:3*IFROM)
  IMATCH = GET_MATCH(XYZFROM,VERTS,ITO-1)
  IF(IMATCH/=0)THEN
    MAPVERTS(IFROM)=IMATCH
    CYCLE
  ENDIF
  MAPVERTS(IFROM)=ITO
  VERTS(3*ITO-2:3*ITO)=VERTS(3*IFROM-2:3*IFROM)
  ITO = ITO + 1
END DO
NVERTS=ITO-1
    
! MAP TRIANGLE NODES TO NEW NODES

DO I=1,3*NTRIANGLES
  TRIANGLES(I) = MAPVERTS(TRIANGLES(I) + 1) - 1
END DO

DEALLOCATE(MAPVERTS)

END SUBROUTINE REMOVE_DUPLICATE_ISO_VERTS

! ------------------ ISO_TO_GEOM ------------------------

SUBROUTINE ISO_TO_GEOM(VDATA, LEVEL, &
     IBLANK_CELL, XPLT, NX, YPLT, NY, ZPLT, NZ,&
     XYZVERTS, NXYZVERTS, TRIANGLES, NTRIANGLES)

  INTEGER, INTENT(IN) :: NX, NY, NZ
  REAL(FB), DIMENSION(0:NX,0:NY,0:NZ), INTENT(IN) :: VDATA
  INTEGER, DIMENSION(NX-1,NY-1,NZ-1), INTENT(IN) :: IBLANK_CELL
  REAL(FB), INTENT(IN) :: LEVEL
  REAL(FB), INTENT(IN), DIMENSION(NX) :: XPLT
  REAL(FB), INTENT(IN), DIMENSION(NY) :: YPLT
  REAL(FB), INTENT(IN), DIMENSION(NZ) :: ZPLT
     
  REAL(FB), INTENT(OUT), DIMENSION(:), POINTER :: XYZVERTS
  INTEGER, INTENT(OUT), DIMENSION(:), POINTER :: TRIANGLES
  INTEGER, INTENT(OUT) :: NTRIANGLES, NXYZVERTS
  
  REAL(FB), DIMENSION(0:1) :: XX, YY, ZZ
  REAL(FB), DIMENSION(0:7) :: VALS
  REAL(FB), DIMENSION(0:35) :: XYZVERTS_LOCAL
  INTEGER :: NXYZVERTS_LOCAL
  INTEGER, DIMENSION(0:14) :: TRIS_LOCAL
  INTEGER :: NTRIS_LOCAL
  INTEGER :: NXYZVERTS_MAX, NTRIANGLES_MAX
  REAL(FB) :: VMIN, VMAX
  
  INTEGER :: I, J, K
     
  INTEGER :: MEMERR
  
  NULLIFY(XYZVERTS)
  NULLIFY(TRIANGLES)
  NTRIANGLES=0
  NXYZVERTS=0
  NXYZVERTS_MAX=1000
  NTRIANGLES_MAX=1000
  ALLOCATE(XYZVERTS(3*NXYZVERTS_MAX),STAT=MEMERR)
  CALL ChkMemErr('ISO_TO_GEOM','XYZVERTS',MEMERR)
  ALLOCATE(TRIANGLES(3*NTRIANGLES_MAX),STAT=MEMERR)
  CALL ChkMemErr('ISO_TO_GEOM','TRIANGLES',MEMERR)
     
  DO I=1, NX-1
    XX(0) = XPLT(I)
    XX(1) = XPLT(I+1)
    DO J=1,NY-1
      YY(0) = YPLT(J);
      YY(1) = YPLT(J+1);
      DO K=1,NZ-1
        IF (IBLANK_CELL(I,J,K) == 0) CYCLE
        
        VALS(0) = VDATA(  I,  J,  K)
        VALS(1) = VDATA(  I,J+1,  K)
        VALS(2) = VDATA(I+1,J+1,  K)
        VALS(3) = VDATA(I+1,  J,  K)
        VALS(4) = VDATA(  I,  J,K+1)
        VALS(5) = VDATA(  I,J+1,K+1)
        VALS(6) = VDATA(I+1,J+1,K+1)
        VALS(7) = VDATA(I+1,  J,K+1)

        VMIN = MIN(VALS(0),VALS(1),VALS(2),VALS(3),VALS(4),VALS(5),VALS(6),VALS(7))
        VMAX = MAX(VALS(0),VALS(1),VALS(2),VALS(3),VALS(4),VALS(5),VALS(6),VALS(7))
        IF (VMIN > LEVEL.OR.VMAX < LEVEL) CYCLE
           
        ZZ(0) = ZPLT(K);
        ZZ(1) = ZPLT(K+1);

        CALL GETISOBOX(XX,YY,ZZ,VALS,LEVEL,&
            XYZVERTS_LOCAL,NXYZVERTS_LOCAL,TRIS_LOCAL,NTRIS_LOCAL)

        IF (NXYZVERTS_LOCAL > 0.OR.NTRIS_LOCAL > 0) THEN
          CALL UPDATEISOSURFACE(XYZVERTS_LOCAL, NXYZVERTS_LOCAL, TRIS_LOCAL, NTRIS_LOCAL, &
          XYZVERTS, NXYZVERTS, NXYZVERTS_MAX, TRIANGLES, NTRIANGLES, NTRIANGLES_MAX)
        ENDIF
      END DO
    END DO
  END DO
  RETURN     
END SUBROUTINE ISO_TO_GEOM

! ------------------ ISO_HEADER_OUT ------------------------

SUBROUTINE ISO_HEADER_OUT(LU_ISO,ISO_LEVELS,NISO_LEVELS)

  INTEGER, INTENT(IN) :: NISO_LEVELS
  INTEGER, INTENT(IN) :: LU_ISO
  REAL(FB), INTENT(IN), DIMENSION(NISO_LEVELS) :: ISO_LEVELS
  
  INTEGER :: VERSION=1
  INTEGER :: I
  INTEGER :: ONE=1,ZERO=0
  
  WRITE(LU_ISO) ONE
  WRITE(LU_ISO) VERSION
  WRITE(LU_ISO) NISO_LEVELS
  IF (NISO_LEVELS>0) WRITE(LU_ISO) (ISO_LEVELS(I),I=1,NISO_LEVELS)
  WRITE(LU_ISO) ZERO  ! no integer header
  WRITE(LU_ISO) ZERO, ZERO  ! no static nodes or triangles
  RETURN
END SUBROUTINE ISO_HEADER_OUT           

! ------------------ ISO_OUT ------------------------

SUBROUTINE ISO_OUT(LU_ISO,STIME,VERTS,NVERTS,TRIANGLES,SURFACES,NTRIANGLES)
  INTEGER, INTENT(IN) :: LU_ISO
  REAL(FB), INTENT(IN) :: STIME
  INTEGER, INTENT(IN) :: NVERTS,  NTRIANGLES
  REAL(FB), INTENT(IN), DIMENSION(:), POINTER :: VERTS
  INTEGER, INTENT(IN), DIMENSION(:), POINTER :: TRIANGLES
  INTEGER, INTENT(IN), DIMENSION(:), POINTER :: SURFACES
  
  INTEGER :: GEOM_TYPE=0
  
  INTEGER :: I

  WRITE(LU_ISO) STIME, GEOM_TYPE ! dynamic geometry (displayed only at time STIME)
  WRITE(LU_ISO) NVERTS,NTRIANGLES
  IF (NVERTS>0) THEN
     WRITE(LU_ISO) (VERTS(I),I=1,3*NVERTS)
  ENDIF
  IF (NTRIANGLES>0) THEN
     WRITE(LU_ISO) (1+TRIANGLES(I),I=1,3*NTRIANGLES)
     WRITE(LU_ISO) (SURFACES(I),I=1,NTRIANGLES)
  ENDIF

  RETURN
END SUBROUTINE ISO_OUT           

! ------------------ MERGE_GEOM ------------------------

SUBROUTINE MERGE_GEOM(  TRIS_TO,  SURFACES_TO,  NTRIS_TO,  NODES_TO,  NNODES_TO,&
                      TRIS_FROM,SURFACES_FROM,NTRIS_FROM,NODES_FROM,NNODES_FROM)

  INTEGER, INTENT(INOUT), DIMENSION(:), POINTER :: TRIS_TO, SURFACES_TO
  REAL(FB), INTENT(INOUT), DIMENSION(:), POINTER :: NODES_TO
  INTEGER, INTENT(INOUT) :: NTRIS_TO,NNODES_TO
  
  INTEGER, DIMENSION(:), POINTER :: TRIS_FROM, SURFACES_FROM
  REAL(FB), DIMENSION(:), POINTER :: NODES_FROM
  INTEGER, INTENT(IN) :: NTRIS_FROM,NNODES_FROM
  
  INTEGER :: NNODES_NEW, NTRIS_NEW, N
  
  NNODES_NEW = NNODES_TO + NNODES_FROM
  NTRIS_NEW = NTRIS_TO + NTRIS_FROM
  
  CALL REALLOCATE_F('MERGE_GEOM','NODES_TO',NODES_TO,3*NNODES_TO,3*NNODES_NEW)
  CALL REALLOCATE_I('MERGE_GEOM','TRIS_TO',TRIS_TO,3*NTRIS_TO,3*NTRIS_NEW)
  CALL REALLOCATE_I('MERGE_GEOM','SURFACES_TO',SURFACES_TO,NTRIS_TO,NTRIS_NEW)
  
  NODES_TO(1+3*NNODES_TO:3*NNODES_NEW) = NODES_FROM(1:3*NNODES_FROM)
  TRIS_TO(1+3*NTRIS_TO:3*NTRIS_NEW) = TRIS_FROM(1:3*NTRIS_FROM)
  SURFACES_TO(1+NTRIS_TO:NTRIS_NEW) = SURFACES_FROM(1:NTRIS_FROM)
  
  DO N=1,3*NTRIS_FROM
    TRIS_TO(3*NTRIS_TO+N) = TRIS_TO(3*NTRIS_TO+N) + NNODES_TO
  END DO
  NNODES_TO = NNODES_NEW
  NTRIS_TO = NTRIS_NEW
END SUBROUTINE MERGE_GEOM

! ------------------ GETISOBOX ------------------------

SUBROUTINE GETISOBOX(X,Y,Z,VALS,LEVEL,XYZV_LOCAL,NXYZV,TRIS,NTRIS)
  IMPLICIT NONE
  REAL(FB), DIMENSION(0:1), INTENT(IN) :: X, Y, Z
  REAL(FB), DIMENSION(0:7), INTENT(IN) :: VALS
  REAL(FB), INTENT(OUT), DIMENSION(0:35) :: XYZV_LOCAL
  INTEGER, INTENT(OUT), DIMENSION(0:14) :: TRIS
  REAL(FB), INTENT(IN) :: LEVEL
  INTEGER, INTENT(OUT) :: NXYZV
  INTEGER, INTENT(OUT) :: NTRIS

  INTEGER :: I, J

  INTEGER, DIMENSION(0:14) :: COMPCASE=(/0,0,0,-1,0,0,-1,-1,0,0,0,0,-1,-1,0/)

  INTEGER, DIMENSION(0:11,0:1) :: EDGE2VERTEX                                              
  INTEGER, DIMENSION(0:1,0:11) :: EDGE2VERTEXTT
  DATA ((EDGE2VERTEXTT(I,J),I=0,1),J=0,11) /0,1,1,2,2,3,0,3,&
                                              0,4,1,5,2,6,3,7,&
                                              4,5,5,6,6,7,4,7/

  INTEGER, POINTER, DIMENSION(:) :: CASE2
  INTEGER, TARGET,DIMENSION(0:255,0:9) :: CASES
  INTEGER, DIMENSION(0:9,0:255) :: CASEST
  DATA ((CASEST(I,J),I=0,9),J=0,255) /&
  0,0,0,0,0,0,0,0, 0,  0,0,1,2,3,4,5,6,7, 1,  1,1,2,3,0,5,6,7,4, 1,  2,&
  1,2,3,0,5,6,7,4, 2,  3,2,3,0,1,6,7,4,5, 1,  4,0,4,5,1,3,7,6,2, 3,  5,&
  2,3,0,1,6,7,4,5, 2,  6,3,0,1,2,7,4,5,6, 5,  7,3,0,1,2,7,4,5,6, 1,  8,&
  0,1,2,3,4,5,6,7, 2,  9,3,7,4,0,2,6,5,1, 3, 10,2,3,0,1,6,7,4,5, 5, 11,&
  3,0,1,2,7,4,5,6, 2, 12,1,2,3,0,5,6,7,4, 5, 13,0,1,2,3,4,5,6,7, 5, 14,&
  0,1,2,3,4,5,6,7, 8, 15,4,0,3,7,5,1,2,6, 1, 16,4,5,1,0,7,6,2,3, 2, 17,&
  1,2,3,0,5,6,7,4, 3, 18,5,1,0,4,6,2,3,7, 5, 19,2,3,0,1,6,7,4,5, 4, 20,&
  4,5,1,0,7,6,2,3, 6, 21,2,3,0,1,6,7,4,5, 6, 22,3,0,1,2,7,4,5,6,14, 23,&
  4,5,1,0,7,6,2,3, 3, 24,7,4,0,3,6,5,1,2, 5, 25,2,6,7,3,1,5,4,0, 7, 26,&
  3,0,1,2,7,4,5,6, 9, 27,2,6,7,3,1,5,4,0, 6, 28,4,0,3,7,5,1,2,6,11, 29,&
  0,1,2,3,4,5,6,7,12, 30,0,0,0,0,0,0,0,0, 0,  0,5,4,7,6,1,0,3,2, 1, 32,&
  0,3,7,4,1,2,6,5, 3, 33,1,0,4,5,2,3,7,6, 2, 34,4,5,1,0,7,6,2,3, 5, 35,&
  2,3,0,1,6,7,4,5, 3, 36,3,7,4,0,2,6,5,1, 7, 37,6,2,1,5,7,3,0,4, 5, 38,&
  0,1,2,3,4,5,6,7, 9, 39,3,0,1,2,7,4,5,6, 4, 40,3,7,4,0,2,6,5,1, 6, 41,&
  5,6,2,1,4,7,3,0, 6, 42,3,0,1,2,7,4,5,6,11, 43,3,0,1,2,7,4,5,6, 6, 44,&
  1,2,3,0,5,6,7,4,12, 45,0,1,2,3,4,5,6,7,14, 46,0,0,0,0,0,0,0,0, 0,  0,&
  5,1,0,4,6,2,3,7, 2, 48,1,0,4,5,2,3,7,6, 5, 49,0,4,5,1,3,7,6,2, 5, 50,&
  4,5,1,0,7,6,2,3, 8, 51,4,7,6,5,0,3,2,1, 6, 52,1,0,4,5,2,3,7,6,12, 53,&
  4,5,1,0,7,6,2,3,11, 54,0,0,0,0,0,0,0,0, 0,  0,5,1,0,4,6,2,3,7, 6, 56,&
  1,0,4,5,2,3,7,6,14, 57,0,4,5,1,3,7,6,2,12, 58,0,0,0,0,0,0,0,0, 0,  0,&
  4,0,3,7,5,1,2,6,10, 60,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,6,7,3,2,5,4,0,1, 1, 64,0,1,2,3,4,5,6,7, 4, 65,&
  1,0,4,5,2,3,7,6, 3, 66,0,4,5,1,3,7,6,2, 6, 67,2,1,5,6,3,0,4,7, 2, 68,&
  6,7,3,2,5,4,0,1, 6, 69,5,6,2,1,4,7,3,0, 5, 70,0,1,2,3,4,5,6,7,11, 71,&
  3,0,1,2,7,4,5,6, 3, 72,0,1,2,3,4,5,6,7, 6, 73,7,4,0,3,6,5,1,2, 7, 74,&
  2,3,0,1,6,7,4,5,12, 75,7,3,2,6,4,0,1,5, 5, 76,1,2,3,0,5,6,7,4,14, 77,&
  1,2,3,0,5,6,7,4, 9, 78,0,0,0,0,0,0,0,0, 0,  0,4,0,3,7,5,1,2,6, 3, 80,&
  0,3,7,4,1,2,6,5, 6, 81,2,3,0,1,6,7,4,5, 7, 82,5,1,0,4,6,2,3,7,12, 83,&
  2,1,5,6,3,0,4,7, 6, 84,0,1,2,3,4,5,6,7,10, 85,5,6,2,1,4,7,3,0,12, 86,&
  0,0,0,0,0,0,0,0, 0,  0,0,1,2,3,4,5,6,7, 7, 88,7,4,0,3,6,5,1,2,12, 89,&
  3,0,1,2,7,4,5,6,13, 90,0,0,0,0,0,0,0,0, 0,  0,7,3,2,6,4,0,1,5,12, 92,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  5,4,7,6,1,0,3,2, 2, 96,6,2,1,5,7,3,0,4, 6, 97,2,1,5,6,3,0,4,7, 5, 98,&
  2,1,5,6,3,0,4,7,14, 99,1,5,6,2,0,4,7,3, 5,100,1,5,6,2,0,4,7,3,12,101,&
  1,5,6,2,0,4,7,3, 8,102,0,0,0,0,0,0,0,0, 0,  0,5,4,7,6,1,0,3,2, 6,104,&
  0,4,5,1,3,7,6,2,10,105,2,1,5,6,3,0,4,7,12,106,0,0,0,0,0,0,0,0, 0,  0,&
  5,6,2,1,4,7,3,0,11,108,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,7,6,5,4,3,2,1,0, 5,112,0,4,5,1,3,7,6,2,11,113,&
  6,5,4,7,2,1,0,3, 9,114,0,0,0,0,0,0,0,0, 0,  0,1,5,6,2,0,4,7,3,14,116,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  7,6,5,4,3,2,1,0,12,120,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,7,6,5,4,3,2,1,0, 1,128,&
  0,1,2,3,4,5,6,7, 3,129,1,2,3,0,5,6,7,4, 4,130,1,2,3,0,5,6,7,4, 6,131,&
  7,4,0,3,6,5,1,2, 3,132,1,5,6,2,0,4,7,3, 7,133,1,5,6,2,0,4,7,3, 6,134,&
  3,0,1,2,7,4,5,6,12,135,3,2,6,7,0,1,5,4, 2,136,4,0,3,7,5,1,2,6, 5,137,&
  7,4,0,3,6,5,1,2, 6,138,2,3,0,1,6,7,4,5,14,139,6,7,3,2,5,4,0,1, 5,140,&
  2,3,0,1,6,7,4,5, 9,141,1,2,3,0,5,6,7,4,11,142,0,0,0,0,0,0,0,0, 0,  0,&
  4,0,3,7,5,1,2,6, 2,144,3,7,4,0,2,6,5,1, 5,145,7,6,5,4,3,2,1,0, 6,146,&
  1,0,4,5,2,3,7,6,11,147,4,0,3,7,5,1,2,6, 6,148,3,7,4,0,2,6,5,1,12,149,&
  1,0,4,5,2,3,7,6,10,150,0,0,0,0,0,0,0,0, 0,  0,0,3,7,4,1,2,6,5, 5,152,&
  4,0,3,7,5,1,2,6, 8,153,0,3,7,4,1,2,6,5,12,154,0,0,0,0,0,0,0,0, 0,  0,&
  0,3,7,4,1,2,6,5,14,156,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,5,1,0,4,6,2,3,7, 3,160,1,2,3,0,5,6,7,4, 7,161,&
  1,0,4,5,2,3,7,6, 6,162,4,5,1,0,7,6,2,3,12,163,3,0,1,2,7,4,5,6, 7,164,&
  0,1,2,3,4,5,6,7,13,165,6,2,1,5,7,3,0,4,12,166,0,0,0,0,0,0,0,0, 0,  0,&
  3,2,6,7,0,1,5,4, 6,168,4,0,3,7,5,1,2,6,12,169,1,2,3,0,5,6,7,4,10,170,&
  0,0,0,0,0,0,0,0, 0,  0,6,7,3,2,5,4,0,1,12,172,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,6,5,4,7,2,1,0,3, 5,176,&
  0,4,5,1,3,7,6,2, 9,177,0,4,5,1,3,7,6,2,14,178,0,0,0,0,0,0,0,0, 0,  0,&
  6,5,4,7,2,1,0,3,12,180,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,5,4,7,6,1,0,3,2,11,184,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  7,3,2,6,4,0,1,5, 2,192,6,5,4,7,2,1,0,3, 6,193,7,3,2,6,4,0,1,5, 6,194,&
  0,3,7,4,1,2,6,5,10,195,3,2,6,7,0,1,5,4, 5,196,3,2,6,7,0,1,5,4,12,197,&
  3,2,6,7,0,1,5,4,14,198,0,0,0,0,0,0,0,0, 0,  0,2,6,7,3,1,5,4,0, 5,200,&
  0,3,7,4,1,2,6,5,11,201,2,6,7,3,1,5,4,0,12,202,0,0,0,0,0,0,0,0, 0,  0,&
  3,2,6,7,0,1,5,4, 8,204,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,5,4,7,6,1,0,3,2, 5,208,3,7,4,0,2,6,5,1,14,209,&
  5,4,7,6,1,0,3,2,12,210,0,0,0,0,0,0,0,0, 0,  0,4,7,6,5,0,3,2,1,11,212,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  6,7,3,2,5,4,0,1, 9,216,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,4,7,6,5,0,3,2,1, 5,224,&
  4,7,6,5,0,3,2,1,12,225,1,5,6,2,0,4,7,3,11,226,0,0,0,0,0,0,0,0, 0,  0,&
  7,6,5,4,3,2,1,0, 9,228,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,2,6,7,3,1,5,4,0,14,232,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  5,4,7,6,1,0,3,2, 8,240,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,0,0,0,0,0,0,0,0, 0,  0,&
  0,0,0,0,0,0,0,0, 0,  0&
  /

  INTEGER, TARGET,DIMENSION(0:14,0:12) :: PATHCCLIST
  INTEGER, DIMENSION(0:12,0:14) :: PATHCCLISTT
  DATA ((PATHCCLISTT(I,J),I=0,12),J=0,14) /&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   3, 0, 1, 2,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   6, 0, 1, 2, 2, 3, 0,-1,-1,-1,-1,-1,-1,&
   6, 0, 1, 2, 3, 4, 5,-1,-1,-1,-1,-1,-1,&
   6, 0, 1, 2, 3, 4, 5,-1,-1,-1,-1,-1,-1,&
   9, 0, 1, 2, 2, 3, 4, 0, 2, 4,-1,-1,-1,&
   9, 0, 1, 2, 2, 3, 0, 4, 5, 6,-1,-1,-1,&
   9, 0, 1, 2, 3, 4, 5, 6, 7, 8,-1,-1,-1,&
   6, 0, 1, 2, 2, 3, 0,-1,-1,-1,-1,-1,-1,&
  12, 0, 1, 5, 1, 4, 5, 1, 2, 4, 2, 3, 4,&
  12, 0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,&
  12, 0, 1, 5, 1, 4, 5, 1, 2, 4, 2, 3, 4,&
  12, 0, 1, 2, 3, 4, 5, 3, 5, 6, 3, 6, 7,&
  12, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,&
  12, 0, 1, 5, 1, 4, 5, 1, 2, 4, 2, 3, 4&
  /

  INTEGER, TARGET,DIMENSION(0:14,0:15) :: PATHCCLIST2
  INTEGER, DIMENSION(0:15,0:14) :: PATHCCLIST2T
  DATA ((PATHCCLIST2T(I,J),I=0,15),J=0,14) /&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   12, 0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   15, 0, 1, 2, 0, 2, 3, 4, 5, 6, 7, 8, 9, 7, 9,10,&
   15, 0, 1, 2, 3, 4, 5, 3, 5, 7, 3, 7, 8, 5, 6, 7,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   12, 0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   12, 0, 1, 2, 3, 4, 6, 3, 6, 7, 4, 5, 6,-1,-1,-1,&
   12, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,-1,-1,-1,&
    0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1&
   /

  INTEGER, POINTER,DIMENSION(:) :: PATH
  INTEGER, TARGET,DIMENSION(0:14,0:12) :: PATHCCWLIST
  INTEGER, DIMENSION(0:12,0:14) :: PATHCCWLISTT
  DATA ((PATHCCWLISTT(I,J),I=0,12),J=0,14) /&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   3, 0, 2, 1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   6, 0, 2, 1, 0, 3, 2,-1,-1,-1,-1,-1,-1,&
   6, 0, 2, 1, 3, 5, 4,-1,-1,-1,-1,-1,-1,&
   6, 0, 2, 1, 3, 5, 4,-1,-1,-1,-1,-1,-1,&
   9, 0, 2, 1, 2, 4, 3, 0, 4, 2,-1,-1,-1,&
   9, 0, 2, 1, 0, 3, 2, 4, 6, 5,-1,-1,-1,&
   9, 0, 2, 1, 3, 5, 4, 6, 8, 7,-1,-1,-1,&
   6, 0, 2, 1, 0, 3, 2,-1,-1,-1,-1,-1,-1,&
  12, 0, 5, 1, 1, 5, 4, 1, 4, 2, 2, 4, 3,&
  12, 0, 2, 1, 0, 3, 2, 4, 6, 5, 4, 7, 6,&
  12, 0, 5, 1, 1, 5, 4, 1, 4, 2, 2, 4, 3,&
  12, 0, 2, 1, 3, 5, 4, 3, 6, 5, 3, 7, 6,&
  12, 0, 2, 1, 3, 5, 4, 6, 8, 7, 9,11,10,&
  12, 0, 5, 1, 1, 5, 4, 1, 4, 2, 2, 4, 3&
   /

  INTEGER, TARGET,DIMENSION(0:14,0:15) :: PATHCCWLIST2
  INTEGER, DIMENSION(0:15,0:14) :: PATHCCWLIST2T
  DATA ((PATHCCWLIST2T(I,J),I=0,15),J=0,14) /&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
  12, 0, 2, 1, 0, 3, 2, 4, 6, 5, 4, 7, 6,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
  15, 0, 2, 1, 0, 3, 2, 4, 6, 5, 7, 9, 8, 7,10, 9,&
  15, 0, 2, 1, 3, 5, 4, 3, 7, 5, 3, 8, 7, 5, 7, 6,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
  12, 0, 2, 1, 0, 3, 2, 4, 6, 5, 4, 7, 6,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
  12, 0, 2, 1, 3, 6, 4, 3, 7, 6, 4, 6, 5,-1,-1,-1,&
  12, 0, 2, 1, 3, 5, 4, 6, 8, 7, 9,11,10,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1&
  /


  INTEGER, POINTER,DIMENSION(:) :: EDGES
  INTEGER, TARGET,DIMENSION(0:14,0:12) :: EDGELIST
  INTEGER, DIMENSION(0:12,0:14) :: EDGELISTT
  DATA ((EDGELISTT(I,J),I=0,12),J=0,14) /&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   3, 0, 4, 3,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   4, 0, 4, 7, 2,-1,-1,-1,-1,-1,-1,-1,-1,&
   6, 0, 4, 3, 7,11,10,-1,-1,-1,-1,-1,-1,&
   6, 0, 4, 3, 6,10, 9,-1,-1,-1,-1,-1,-1,&
   5, 0, 3, 7, 6, 5,-1,-1,-1,-1,-1,-1,-1,&
   7, 0, 4, 7, 2, 6,10, 9,-1,-1,-1,-1,-1,&
   9, 4, 8,11, 2, 3, 7, 6,10, 9,-1,-1,-1,&
   4, 4, 7, 6, 5,-1,-1,-1,-1,-1,-1,-1,-1,&
   6, 2, 6, 9, 8, 4, 3,-1,-1,-1,-1,-1,-1,&
   8, 0, 8,11, 3,10, 9, 1, 2,-1,-1,-1,-1,&
   6, 4, 3, 2,10, 9, 5,-1,-1,-1,-1,-1,-1,&
   8, 4, 8,11, 0, 3, 7, 6, 5,-1,-1,-1,-1,&
  12, 0, 4, 3, 7,11,10, 2, 6, 1, 8, 5, 9,&
   6, 3, 7, 6, 9, 8, 0,-1,-1,-1,-1,-1,-1&
  /

  INTEGER, TARGET,DIMENSION(0:14,0:15) :: EDGELIST2
  INTEGER, DIMENSION(0:15,0:14) :: EDGELIST2T
  DATA ((EDGELIST2T(I,J),I=0,15),J=0,14) /&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   8, 3, 0,10, 7, 0, 4,11,10,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
  11, 7,10, 9, 4, 0, 4, 9, 0, 9, 6, 2,-1,-1,-1,-1,&
   9, 7,10,11, 3, 4, 8, 9, 6, 2,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   8, 0, 8, 9, 1, 3, 2,10,11,-1,-1,-1,-1,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,&
   8, 0, 3, 4, 8,11, 7, 6, 5,-1,-1,-1,-1,-1,-1,-1,&
  12, 4,11, 8, 0, 5, 1, 7, 3, 2, 9,10, 6,-1,-1,-1,&
   0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1&
  /
  
  REAL(FB) :: VMIN, VMAX
  INTEGER :: CASENUM, BIGGER, SIGN, N
  INTEGER, DIMENSION(0:7) :: PRODS=(/1,2,4,8,16,32,64,128/);
  REAL(FB), DIMENSION(0:7) :: XXVAL,YYVAL,ZZVAL
  INTEGER, DIMENSION(0:3) :: IXMIN=(/0,1,4,5/), IXMAX=(/2,3,6,7/)
  INTEGER, DIMENSION(0:3) :: IYMIN=(/0,3,4,7/), IYMAX=(/1,2,5,6/)
  INTEGER, DIMENSION(0:3) :: IZMIN=(/0,1,2,3/), IZMAX=(/4,5,6,7/)
  INTEGER :: TYPE2,THISTYPE2
  INTEGER :: NEDGES,NPATH
  INTEGER :: OUTOFBOUNDS, EDGE, V1, V2
  REAL(FB) :: VAL1, VAL2, DENOM, FACTOR
  REAL(FB) :: XX, YY, ZZ

  EDGE2VERTEX=TRANSPOSE(EDGE2VERTEXTT)
  CASES=TRANSPOSE(CASEST)
  PATHCCLIST=TRANSPOSE(PATHCCLISTT)
  PATHCCLIST2=TRANSPOSE(PATHCCLIST2T)
  PATHCCWLIST=TRANSPOSE(PATHCCWLISTT)
  PATHCCWLIST2=TRANSPOSE(PATHCCWLIST2T)
  EDGELIST=TRANSPOSE(EDGELISTT)
  EDGELIST2=TRANSPOSE(EDGELIST2T)

  VMIN=MIN(VALS(0),VALS(1),VALS(2),VALS(3),VALS(4),VALS(5),VALS(6),VALS(7))
  VMAX=MAX(VALS(0),VALS(1),VALS(2),VALS(3),VALS(4),VALS(5),VALS(6),VALS(7))

  NXYZV=0
  NTRIS=0

  IF (VMIN>LEVEL.OR.VMAX<LEVEL) RETURN

  CASENUM=0
  BIGGER=0
  SIGN=1

  DO N = 0, 7
    IF (VALS(N)>LEVEL) THEN
      BIGGER=BIGGER+1
      CASENUM = CASENUM + PRODS(N);
    ENDIF
  END DO

! THERE ARE MORE NODES GREATER THAN THE ISO-SURFACE LEVEL THAN BELOW, SO 
!   SOLVE THE COMPLEMENTARY PROBLEM 

  IF (BIGGER > 4) THEN
    SIGN=-1
    CASENUM=0
    DO N=0, 7
      IF (VALS(N)<LEVEL) THEN
        CASENUM = CASENUM + PRODS(N)
      ENDIF
    END DO
  ENDIF

! STUFF MIN AND MAX GRID DATA INTO A MORE CONVENIENT FORM 
!  ASSUMING THE FOLLOWING GRID NUMBERING SCHEME

!       5-------6
!     / |      /| 
!   /   |     / | 
!  4 -------7   |
!  |    |   |   |  
!  Z    1---|---2
!  |  Y     |  /
!  |/       |/
!  0--X-----3     


  DO N=0, 3
    XXVAL(IXMIN(N)) = X(0);
    XXVAL(IXMAX(N)) = X(1);
    YYVAL(IYMIN(N)) = Y(0);
    YYVAL(IYMAX(N)) = Y(1);
    ZZVAL(IZMIN(N)) = Z(0);
    ZZVAL(IZMAX(N)) = Z(1);
  END DO

  IF (CASENUM<=0.OR.CASENUM>=255) THEN ! NO ISO-SURFACE 
    NTRIS=0
    RETURN
  ENDIF

  CASE2(0:9) => CASES(CASENUM,0:9)
  TYPE2 = CASE2(8);
  IF (TYPE2==0) THEN
    NTRIS=0
    RETURN
  ENDIF

  IF (COMPCASE(TYPE2) == -1) THEN
    THISTYPE2=SIGN
  ELSE
    THISTYPE2=1
  ENDIF
  
  IF (THISTYPE2 /= -1) THEN
    !EDGES = &(EDGELIST[TYPE][1]);
    EDGES(-1:11) => EDGELIST(TYPE2,0:12)
    IF (SIGN >=0) THEN
     ! PATH = &(PATHCCLIST[TYPE][1])   !  CONSTRUCT TRIANGLES CLOCK WISE
      PATH(-1:11) => PATHCCLIST(TYPE2,0:12)
    ELSE
     ! PATH = &(PATHCCWLIST[TYPE][1])  !  CONSTRUCT TRIANGLES COUNTER CLOCKWISE 
      PATH(-1:11) => PATHCCWLIST(TYPE2,0:12)
    ENDIF
  ELSE
    !EDGES = &(EDGELIST2[TYPE][1]);
    EDGES(-1:11) => EDGELIST2(TYPE2,0:12)
    IF (SIGN > 0) THEN
     ! PATH = &(PATHCCLIST2[TYPE][1])  !  CONSTRUCT TRIANGLES CLOCK WISE
      PATH(-1:14) => PATHCCLIST2(TYPE2,0:15)
    ELSE
     ! PATH = &(PATHCCWLIST2[TYPE][1]) !  CONSTRUCT TRIANGLES COUNTER CLOCKWISE
      PATH(-1:14) => PATHCCWLIST2(TYPE2,0:15)
    ENDIF   
  ENDIF
  NPATH = PATH(-1);
  NEDGES = EDGES(-1);
  
  OUTOFBOUNDS=0
  DO N=0,NEDGES-1
    EDGE = EDGES(N)
    V1 = CASE2(EDGE2VERTEX(EDGE,0));
    V2 = CASE2(EDGE2VERTEX(EDGE,1));
    VAL1 = VALS(V1)-LEVEL
    VAL2 = VALS(V2)-LEVEL
    DENOM = VAL2 - VAL1
    FACTOR = 0.5_FB
    IF (DENOM /= 0.0_FB)FACTOR = -VAL1/DENOM
    XX = FMIX(FACTOR,XXVAL(V1),XXVAL(V2));
    YY = FMIX(FACTOR,YYVAL(V1),YYVAL(V2));
    ZZ = FMIX(FACTOR,ZZVAL(V1),ZZVAL(V2));
    XYZV_LOCAL(3*N) = XX;
    XYZV_LOCAL(3*N+1) = YY;
    XYZV_LOCAL(3*N+2) = ZZ;

  END DO

! COPY COORDINATES TO OUTPUT ARRAY

  NXYZV = NEDGES;
  NTRIS = NPATH/3;
  IF (NPATH > 0) THEN
    TRIS(0:NPATH-1) = PATH(0:NPATH-1)
  ENDIF
  RETURN
END SUBROUTINE GETISOBOX

! ------------------ UPDATEISOSURFACE ------------------------

SUBROUTINE UPDATEISOSURFACE(XYZVERTS_BOX, NXYZVERTS_BOX, TRIS_BOX, NTRIS_BOX,  &
                            XYZVERTS, NXYZVERTS, NXYZVERTS_MAX, TRIANGLES, NTRIANGLES, NTRIANGLES_MAX)
  REAL(FB), INTENT(IN), DIMENSION(0:35) :: XYZVERTS_BOX
  INTEGER, INTENT(IN) :: NXYZVERTS_BOX, NTRIS_BOX
  INTEGER, INTENT(IN), DIMENSION(0:14) :: TRIS_BOX
  REAL(FB), POINTER, DIMENSION(:) :: XYZVERTS
  INTEGER, INTENT(INOUT) :: NXYZVERTS, NXYZVERTS_MAX, NTRIANGLES, NTRIANGLES_MAX
  INTEGER, POINTER, DIMENSION(:) :: TRIANGLES
  
  INTEGER :: NXYZVERTS_NEW, NTRIANGLES_NEW
    
  NXYZVERTS_NEW = NXYZVERTS + NXYZVERTS_BOX
  NTRIANGLES_NEW = NTRIANGLES + NTRIS_BOX
  IF (1+NXYZVERTS_NEW > NXYZVERTS_MAX) THEN
    NXYZVERTS_MAX = 1+NXYZVERTS_NEW+1000
    CALL REALLOCATE_F('UPDATEISOSURFACES','XYZVERTS',XYZVERTS,3*NXYZVERTS,3*NXYZVERTS_MAX)
  ENDIF
  IF (1+NTRIANGLES_NEW > NTRIANGLES_MAX) THEN
    NTRIANGLES_MAX = 1+NTRIANGLES_NEW+1000
    CALL REALLOCATE_I('UPDATEISOSURFACES','TRIANGLES',TRIANGLES,3*NTRIANGLES,3*NTRIANGLES_MAX)
  ENDIF
  XYZVERTS(1+3*NXYZVERTS:3*NXYZVERTS_NEW) = XYZVERTS_BOX(0:3*NXYZVERTS_BOX-1)
  TRIANGLES(1+3*NTRIANGLES:3*NTRIANGLES_NEW) = NXYZVERTS+TRIS_BOX(0:3*NTRIS_BOX-1)
  NXYZVERTS = NXYZVERTS_NEW
  NTRIANGLES = NTRIANGLES_NEW
  RETURN
END SUBROUTINE UPDATEISOSURFACE

! ------------------ REALLOCATE_I ------------------------

SUBROUTINE REALLOCATE_I(ROUTINE,VAR,VALS,OLDSIZE,NEWSIZE)
  CHARACTER(*), INTENT(IN) :: ROUTINE, VAR
  INTEGER, DIMENSION(:), POINTER :: VALS
  INTEGER, INTENT(IN) :: OLDSIZE, NEWSIZE
  INTEGER, DIMENSION(:), ALLOCATABLE :: VALS_TEMP
  INTEGER :: MEMERR
  
  IF (OLDSIZE > 0) THEN
    ALLOCATE(VALS_TEMP(OLDSIZE),STAT=MEMERR)
    CALL ChkMemErr(ROUTINE,VAR//'_TEMP',MEMERR)
    VALS_TEMP(1:OLDSIZE) = VALS(1:OLDSIZE)
    DEALLOCATE(VALS)
  ENDIF
  ALLOCATE(VALS(NEWSIZE),STAT=MEMERR)
  CALL ChkMemErr(ROUTINE,VAR,MEMERR)
  IF (OLDSIZE > 0) THEN
    VALS(1:OLDSIZE)=VALS_TEMP(1:OLDSIZE)
    DEALLOCATE(VALS_TEMP)
  ENDIF
  RETURN
END SUBROUTINE REALLOCATE_I

! ------------------ REALLOCATE_F ------------------------

SUBROUTINE REALLOCATE_F(ROUTINE,VAR,VALS,OLDSIZE,NEWSIZE)
  CHARACTER(*), INTENT(IN) :: ROUTINE,VAR
  REAL(FB), INTENT(INOUT), DIMENSION(:), POINTER :: VALS
  INTEGER, INTENT(IN) :: OLDSIZE, NEWSIZE
  REAL(FB), DIMENSION(:), ALLOCATABLE :: VALS_TEMP
  INTEGER :: MEMERR
  
  IF (OLDSIZE > 0) THEN
    ALLOCATE(VALS_TEMP(OLDSIZE),STAT=MEMERR)
    CALL ChkMemErr(ROUTINE,VAR//'_TEMP',MEMERR)
    VALS_TEMP(1:OLDSIZE) = VALS(1:OLDSIZE)
    DEALLOCATE(VALS)
  ENDIF
  ALLOCATE(VALS(NEWSIZE),STAT=MEMERR)
  CALL ChkMemErr(ROUTINE,VAR,MEMERR)
  IF (OLDSIZE > 0) THEN
    VALS(1:OLDSIZE)=VALS_TEMP(1:OLDSIZE)
    DEALLOCATE(VALS_TEMP)
  ENDIF
  RETURN
END SUBROUTINE REALLOCATE_F

! ------------------ FMIX ------------------------

REAL(FB) FUNCTION FMIX(F,A,B)
  REAL(FB), INTENT(IN) :: F, A, B

  FMIX = (1.0_FB-F)*A + F*B
  RETURN
END FUNCTION FMIX

! ------------------ SMOKE3D_TO_FILE ------------------------

SUBROUTINE SMOKE3D_TO_FILE(LU_SMOKE3D,LU_SMOKE3D_SIZE,TIME,DX,EXTCOEF,SMOKE_TYPE,VALS,NX,NY,NZ,HRRPUV_MAX_SMV)

  INTEGER, INTENT(IN) :: NX,NY,NZ
  INTEGER, INTENT(INOUT) :: LU_SMOKE3D, LU_SMOKE3D_SIZE
  REAL(FB), INTENT(IN) :: TIME, DX, EXTCOEF
  INTEGER, INTENT(IN) :: SMOKE_TYPE
  REAL(FB), INTENT(IN), DIMENSION(NX*NY*NZ) :: VALS
  REAL(FB), INTENT(IN) :: HRRPUV_MAX_SMV
  
  INTEGER, PARAMETER :: SOOT=1, FIRE=2, OTHER=3
  CHARACTER(LEN=1), DIMENSION(:), POINTER :: BUFFER_IN, BUFFER_OUT
  INTEGER :: NCHARS_IN
  REAL(FB) :: FACTOR,VAL
  REAL(FB) :: CUTMAX
  INTEGER :: I, NCHARS_OUT
  INTEGER :: FIRST, NVALS, ONE=1, VERSION=0
  INTEGER :: MEMERR
  
  NVALS=NX*NY*NZ
  NCHARS_IN=NVALS
  
  IF (NVALS < 1) RETURN
  
  IF (LU_SMOKE3D<0.OR.LU_SMOKE3D_SIZE<0) THEN
     LU_SMOKE3D=ABS(LU_SMOKE3D)
     LU_SMOKE3D_SIZE=ABS(LU_SMOKE3D_SIZE)
     FIRST=1
     WRITE(LU_SMOKE3D_SIZE,*)VERSION
     WRITE(LU_SMOKE3D)ONE,VERSION,0,NX-1,0,NY-1,0,NZ-1
  ELSE
     FIRST=0
  ENDIF
  
  ALLOCATE(BUFFER_IN(NVALS),STAT=MEMERR)
  CALL ChkMemErr('SMOKE3D_TO_FILE','BUFFER_IN',MEMERR)
  ALLOCATE(BUFFER_OUT(NVALS),STAT=MEMERR)
  CALL ChkMemErr('SMOKE3D_TO_FILE','BUFFER_OUT',MEMERR)
  
  IF (SMOKE_TYPE == SOOT) THEN
    FACTOR=-EXTCOEF*DX
    DO I = 1, NVALS
      VAL=MAX(0.0_FB,VALS(I))
      BUFFER_IN(I)=CHAR(INT(254*(1.0_FB-EXP( FACTOR*VAL))))
    END DO
    CALL RLE(BUFFER_IN,NCHARS_IN,BUFFER_OUT,NCHARS_OUT)
  ELSE IF (SMOKE_TYPE == FIRE) THEN
    CUTMAX=HRRPUV_MAX_SMV
    IF (CUTMAX < 0.0_FB)CUTMAX=1.0_FB;
    DO I=1,NVALS
      VAL=MAX(0.0_FB,VALS(I))
      VAL=MIN(CUTMAX,VAL)
      BUFFER_IN(I)=CHAR(INT(254*(VAL/CUTMAX)));
    END DO
    CALL RLE(BUFFER_IN,NCHARS_IN,BUFFER_OUT,NCHARS_OUT)
  ELSE
    NCHARS_OUT=0
  ENDIF
  
  WRITE(LU_SMOKE3D_SIZE,*)TIME,NCHARS_IN,NCHARS_OUT
  WRITE(LU_SMOKE3D)TIME
  WRITE(LU_SMOKE3D)NCHARS_IN,NCHARS_OUT
  IF (NCHARS_OUT > 0)WRITE(LU_SMOKE3D)(BUFFER_OUT(I),I=1,NCHARS_OUT)
  
  DEALLOCATE(BUFFER_IN)
  DEALLOCATE(BUFFER_OUT)
  
 END SUBROUTINE SMOKE3D_TO_FILE    

! ------------------ RLE ------------------------

SUBROUTINE RLE(BUFFER_IN, NCHARS_IN, BUFFER_OUT, NCHARS_OUT)

  INTEGER, INTENT(IN) :: NCHARS_IN
  CHARACTER(LEN=1), INTENT(IN), DIMENSION(NCHARS_IN) :: BUFFER_IN
  CHARACTER(LEN=1), INTENT(OUT), DIMENSION(:), POINTER :: BUFFER_OUT
  INTEGER, INTENT(OUT) :: NCHARS_OUT
  
  CHARACTER(LEN=1) :: MARK=CHAR(255),THISCHAR,LASTCHAR
  INTEGER :: N,N2,NREPEATS
  
   NREPEATS=1
   LASTCHAR=MARK
   N2=1
   DO N=1,NCHARS_IN
     THISCHAR=BUFFER_IN(N)
     IF (THISCHAR == LASTCHAR) THEN
       NREPEATS=NREPEATS+1
     ELSE
       NREPEATS=1
     ENDIF
     IF (NREPEATS >=1.AND.NREPEATS <= 3) THEN
       BUFFER_OUT(N2)=THISCHAR
       LASTCHAR=THISCHAR
     ELSE 
       IF (NREPEATS == 4) THEN
         N2=N2-3
         BUFFER_OUT(N2)=MARK
         BUFFER_OUT(N2+1)=THISCHAR
         N2=N2+2
       ELSE
         N2=N2-1
       ENDIF
       BUFFER_OUT(N2)=CHAR(NREPEATS)
       IF (NREPEATS == 254) THEN
         NREPEATS=1
         LASTCHAR=MARK
       ENDIF
     ENDIF
     N2=N2+1
   END DO
   NCHARS_OUT=N2-1
   RETURN
END SUBROUTINE RLE

END MODULE ISOSMOKE            
