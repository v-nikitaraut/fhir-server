ALTER PROCEDURE dbo.HardDeleteResource
   @ResourceTypeId smallint
  ,@ResourceId varchar(64)
  ,@KeepCurrentVersion bit
  ,@IsResourceChangeCaptureEnabled bit
AS
set nocount on
DECLARE @SP varchar(100) = object_name(@@procid)
       ,@Mode varchar(200) = 'RT='+convert(varchar,@ResourceTypeId)+' R='+@ResourceId+' V='+convert(varchar,@KeepCurrentVersion)+' CC='+convert(varchar,@IsResourceChangeCaptureEnabled)
       ,@st datetime = getUTCdate()
       ,@TransactionId bigint

BEGIN TRY
  IF @IsResourceChangeCaptureEnabled = 1 EXECUTE dbo.MergeResourcesBeginTransaction @Count = 1, @TransactionId = @TransactionId OUT

  IF @KeepCurrentVersion = 0
    BEGIN TRANSACTION

  DECLARE @SurrogateIds TABLE (ResourceSurrogateId BIGINT NOT NULL)

  IF @IsResourceChangeCaptureEnabled = 1 AND NOT EXISTS (SELECT * FROM dbo.Parameters WHERE Id = 'InvisibleHistory.IsEnabled' AND Number = 0)
    UPDATE dbo.Resource
      SET IsDeleted = 1
         ,RawResource = 0xF -- invisible value
         ,SearchParamHash = NULL
         ,HistoryTransactionId = @TransactionId
      OUTPUT deleted.ResourceSurrogateId INTO @SurrogateIds
      WHERE ResourceTypeId = @ResourceTypeId
        AND ResourceId = @ResourceId
        AND (@KeepCurrentVersion = 0 OR IsHistory = 1)
        AND RawResource <> 0xF
  ELSE
    DELETE dbo.Resource
      OUTPUT deleted.ResourceSurrogateId INTO @SurrogateIds
      WHERE ResourceTypeId = @ResourceTypeId
        AND ResourceId = @ResourceId
        AND (@KeepCurrentVersion = 0 OR IsHistory = 1)
        AND RawResource <> 0xF

  IF @KeepCurrentVersion = 0
  BEGIN
    -- PAGLOCK allows deallocation of empty page without waiting for ghost cleanup 
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.ResourceWriteClaim B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.ReferenceSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenSearchParamHighCard B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM dbo.TokenSearchParam WHERE ResourceTypeId = @ResourceTypeId AND ResourceSurrogateId IN (SELECT ResourceSurrogateId FROM @SurrogateIds) OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenText B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM dbo.StringSearchParam WHERE ResourceTypeId = @ResourceTypeId AND ResourceSurrogateId IN (SELECT ResourceSurrogateId FROM @SurrogateIds) OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.UriSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.NumberSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.QuantitySearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.DateTimeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.ReferenceTokenCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenTokenCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenDateTimeCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenQuantityCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenStringCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
    DELETE FROM B FROM @SurrogateIds A INNER LOOP JOIN dbo.TokenNumberNumberCompositeSearchParam B WITH (INDEX = 1, FORCESEEK, PAGLOCK) ON B.ResourceTypeId = @ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId OPTION (MAXDOP 1)
  END
  
  IF @@trancount > 0 COMMIT TRANSACTION

  IF @IsResourceChangeCaptureEnabled = 1 EXECUTE dbo.MergeResourcesCommitTransaction @TransactionId

  EXECUTE dbo.LogEvent @Process=@SP,@Mode=@Mode,@Status='End',@Start=@st
END TRY
BEGIN CATCH
  IF @@trancount > 0 ROLLBACK TRANSACTION
  EXECUTE dbo.LogEvent @Process=@SP,@Mode=@Mode,@Status='Error',@Start=@st;
  THROW
END CATCH
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'u' AND name = 'StringSearchParam')
  EXECUTE sp_rename 'StringSearchParam', 'StringSearchParam_Table'
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'v' AND name = 'StringSearchParam')
  DROP VIEW dbo.StringSearchParam
GO
IF object_id('tempdb..#RTs') IS NOT NULL DROP TABLE #RTs
GO
DECLARE @Template varchar(max) = '
IF object_id(''StringSearchParam_XXX'') IS NULL
  CREATE TABLE dbo.StringSearchParam_XXX
  (
      ResourceTypeId       smallint      NOT NULL
     ,ResourceSurrogateId  bigint        NOT NULL
     ,SearchParamId        smallint      NOT NULL
     ,Text                 nvarchar(256) COLLATE Latin1_General_100_CI_AI_SC NOT NULL 
     ,TextOverflow         nvarchar(max) COLLATE Latin1_General_100_CI_AI_SC NULL
     ,IsMin                bit           NOT NULL
     ,IsMax                bit           NOT NULL

     ,CONSTRAINT CHK_StringSearchParam_XXX_ResourceTypeId_XXX CHECK (ResourceTypeId = XXX)
  )

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = object_id(''StringSearchParam_XXX'') AND name = ''IXC_ResourceSurrogateId_SearchParamId'')
  CREATE CLUSTERED INDEX IXC_ResourceSurrogateId_SearchParamId ON dbo.StringSearchParam_XXX (ResourceSurrogateId, SearchParamId) 
    WITH (DATA_COMPRESSION = PAGE)

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = object_id(''StringSearchParam_XXX'') AND name = ''IX_SearchParamId_Text_INCLUDE_TextOverflow_IsMin_IsMax'')
  CREATE INDEX IX_SearchParamId_Text_INCLUDE_TextOverflow_IsMin_IsMax ON dbo.StringSearchParam_XXX (SearchParamId, Text) INCLUDE (TextOverflow, IsMin, IsMax) 
    WITH (DATA_COMPRESSION = PAGE)'
       ,@CreateTable varchar(max)
       ,@CreateView varchar(max) = '
CREATE VIEW dbo.StringSearchParam
AS'
       ,@InsertTrigger varchar(max) = '
CREATE TRIGGER dbo.StringSearchParamIns ON dbo.StringSearchParam INSTEAD OF INSERT
AS
set nocount on'
       ,@DeleteTrigger varchar(max) = '
CREATE TRIGGER dbo.StringSearchParamDel ON dbo.StringSearchParam INSTEAD OF DELETE
AS
set nocount on'

SELECT RT
  INTO #RTs
  FROM (
SELECT RT = 4
UNION SELECT 14
UNION SELECT 15
UNION SELECT 19
UNION SELECT 28
UNION SELECT 35
UNION SELECT 40
UNION SELECT 44
UNION SELECT 53
UNION SELECT 61
UNION SELECT 62
UNION SELECT 76
UNION SELECT 79
UNION SELECT 96
UNION SELECT 100
UNION SELECT 103
UNION SELECT 108
UNION SELECT 110
UNION SELECT 138
      ) A

DECLARE @RT varchar(100)
       ,@First bit = 1
WHILE EXISTS (SELECT * FROM #RTs)
BEGIN
  SET @RT = (SELECT TOP 1 RT FROM #RTs)
  SET @CreateTable = @Template
  SET @CreateTable = replace(@CreateTable,'XXX',@RT)
  --PRINT @CreateTable
  EXECUTE(@CreateTable)
  
  IF @First = 0
    SET @CreateView = @CreateView + '
UNION ALL'
  
  SET @CreateView = @CreateView + '
SELECT *, IsHistory = convert(bit,0) FROM dbo.StringSearchParam_'+@RT

  SET @First = 0

  SET @InsertTrigger = @InsertTrigger + '
INSERT INTO dbo.StringSearchParam_'+@RT+' 
        (ResourceTypeId,ResourceSurrogateId,SearchParamId,Text,TextOverflow,IsMin,IsMax) 
  SELECT ResourceTypeId,ResourceSurrogateId,SearchParamId,Text,TextOverflow,IsMin,IsMax 
    FROM Inserted 
    WHERE ResourceTypeId = '+@RT

  SET @DeleteTrigger = @DeleteTrigger + '
DELETE FROM dbo.StringSearchParam_'+@RT+' WHERE ResourceTypeId = '+@RT+' AND ResourceSurrogateId IN (SELECT ResourceSurrogateId FROM Deleted WHERE ResourceTypeId = '+@RT+')'

  DELETE FROM #RTs WHERE RT = @RT
END

--PRINT @CreateView
EXECUTE(@CreateView)
EXECUTE(@InsertTrigger)
EXECUTE(@DeleteTrigger)
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'u' AND name = 'TokenSearchParam')
  EXECUTE sp_rename 'TokenSearchParam', 'TokenSearchParam_Table'
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'v' AND name = 'TokenSearchParam')
  DROP VIEW dbo.TokenSearchParam
GO
IF object_id('tempdb..#RTs') IS NOT NULL DROP TABLE #RTs
GO
DECLARE @Template varchar(max) = '
IF object_id(''TokenSearchParam_XXX'') IS NULL
  CREATE TABLE dbo.TokenSearchParam_XXX
  (
      ResourceTypeId       smallint     NOT NULL
     ,ResourceSurrogateId  bigint       NOT NULL
     ,SearchParamId        smallint     NOT NULL
     ,SystemId             int          NULL
     ,Code                 varchar(256) COLLATE Latin1_General_100_CS_AS NOT NULL
     ,CodeOverflow         varchar(max) COLLATE Latin1_General_100_CS_AS NULL
   
     ,CONSTRAINT CHK_TokenSearchParam_XXX_CodeOverflow CHECK (len(Code) = 256 OR CodeOverflow IS NULL)
     ,CONSTRAINT CHK_TokenSearchParam_XXX_ResourceTypeId_XXX CHECK (ResourceTypeId = XXX)
  )

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = object_id(''TokenSearchParam_XXX'') AND name = ''IXC_ResourceSurrogateId_SearchParamId'')
  CREATE CLUSTERED INDEX IXC_ResourceSurrogateId_SearchParamId ON dbo.TokenSearchParam_XXX (ResourceSurrogateId, SearchParamId) 
    WITH (DATA_COMPRESSION = PAGE)

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = object_id(''TokenSearchParam_XXX'') AND name = ''IX_SearchParamId_Code_INCLUDE_SystemId'')
  CREATE INDEX IX_SearchParamId_Code_INCLUDE_SystemId ON dbo.TokenSearchParam_XXX (SearchParamId, Code) INCLUDE (SystemId) 
    WITH (DATA_COMPRESSION = PAGE)'
       ,@CreateTable varchar(max)
       ,@CreateView varchar(max) = '
CREATE VIEW dbo.TokenSearchParam
AS'
       ,@InsertTrigger varchar(max) = '
CREATE TRIGGER dbo.TokenSearchParamIns ON dbo.TokenSearchParam INSTEAD OF INSERT
AS
set nocount on'
       ,@DeleteTrigger varchar(max) = '
CREATE TRIGGER dbo.TokenSearchParamDel ON dbo.TokenSearchParam INSTEAD OF DELETE
AS
set nocount on'

SELECT RT
  INTO #RTs
  FROM (
SELECT RT = 4
UNION SELECT 14
UNION SELECT 15
UNION SELECT 19
UNION SELECT 28
UNION SELECT 35
UNION SELECT 40
UNION SELECT 44
UNION SELECT 53
UNION SELECT 61
UNION SELECT 62
UNION SELECT 76
UNION SELECT 79
UNION SELECT 96
UNION SELECT 100
UNION SELECT 103
UNION SELECT 108
UNION SELECT 110
UNION SELECT 138
      ) A

DECLARE @RT varchar(100)
       ,@First bit = 1
WHILE EXISTS (SELECT * FROM #RTs)
BEGIN
  SET @RT = (SELECT TOP 1 RT FROM #RTs)
  SET @CreateTable = @Template
  SET @CreateTable = replace(@CreateTable,'XXX',@RT)
  --PRINT @CreateTable
  EXECUTE(@CreateTable)
  
  IF @First = 0
    SET @CreateView = @CreateView + '
UNION ALL'
  
  SET @CreateView = @CreateView + '
SELECT *, IsHistory = convert(bit,0) FROM dbo.TokenSearchParam_'+@RT

  SET @First = 0

  SET @InsertTrigger = @InsertTrigger + '
INSERT INTO dbo.TokenSearchParam_'+@RT+' 
        (ResourceTypeId,ResourceSurrogateId,SearchParamId,SystemId,Code,CodeOverflow) 
  SELECT ResourceTypeId,ResourceSurrogateId,SearchParamId,SystemId,Code,CodeOverflow 
    FROM Inserted 
    WHERE ResourceTypeId = '+@RT

  SET @DeleteTrigger = @DeleteTrigger + '
DELETE FROM dbo.TokenSearchParam_'+@RT+' WHERE ResourceTypeId = '+@RT+' AND ResourceSurrogateId IN (SELECT ResourceSurrogateId FROM Deleted WHERE ResourceTypeId = '+@RT+')'

  DELETE FROM #RTs WHERE RT = @RT
END

--PRINT @CreateView
EXECUTE(@CreateView)
EXECUTE(@InsertTrigger)
EXECUTE(@DeleteTrigger)
GO
