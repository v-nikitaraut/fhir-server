EXECUTE sp_rename 'Resource', 'ResourceTbl'
GO
CREATE OR ALTER VIEW dbo.Resource
AS
SELECT A.ResourceTypeId
      ,ResourceSurrogateId
      ,ResourceId = CASE WHEN A.ResourceId = '' THEN B.ResourceId ELSE A.ResourceId END
      ,Version
      ,IsHistory
      ,IsDeleted
      ,RequestMethod
      ,RawResource
      ,IsRawResourceMetaSet
      ,SearchParamHash
      ,TransactionId
      ,HistoryTransactionId
      ,OffsetInFile
  FROM dbo.ResourceTbl A
       LEFT OUTER JOIN dbo.ResourceIdIntMap B ON B.ResourceTypeId = A.ResourceTypeId AND B.ResourceIdInt = A.ResourceIdInt
GO
CREATE OR ALTER TRIGGER dbo.ResourceIns ON dbo.Resource INSTEAD OF INSERT
AS
DECLARE @DummyTop bigint = 9223372036854775807
BEGIN
  INSERT INTO dbo.ResourceTbl
      (
           ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceIdInt
          ,Version
          ,IsHistory
          ,IsDeleted
          ,RequestMethod
          ,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
          ,OffsetInFile
      )
    SELECT A.ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceIdInt
          ,Version
          ,IsHistory
          ,IsDeleted
          ,RequestMethod
          ,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
          ,OffsetInFile
      FROM (SELECT TOP (@DummyTop) * FROM Inserted) A
           JOIN dbo.ResourceIdIntMap B ON B.ResourceTypeId = A.ResourceTypeId AND B.ResourceId = A.ResourceId
      OPTION (MAXDOP 1, OPTIMIZE FOR (@DummyTop = 1))
END
GO
CREATE OR ALTER TRIGGER dbo.ResourceUpd ON dbo.Resource INSTEAD OF UPDATE
AS
BEGIN
  IF UPDATE(SearchParamHash) AND NOT UPDATE(IsHistory)
  BEGIN
    UPDATE B
      SET SearchParamHash = A.SearchParamHash
      FROM Inserted A
           JOIN dbo.ResourceTbl B ON B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId
      WHERE A.IsHistory = 0

    RETURN
  END

  IF NOT UPDATE(IsHistory)
    RAISERROR('Generic updates are not supported via Resource view',18,127)

  UPDATE B
    SET IsHistory = A.IsHistory
    FROM Inserted A
         JOIN dbo.ResourceTbl B ON B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId
END
GO
CREATE OR ALTER TRIGGER dbo.ResourceDel ON dbo.Resource INSTEAD OF DELETE
AS
BEGIN
  DELETE FROM A
    FROM dbo.ResourceTbl A
    WHERE EXISTS (SELECT * FROM Deleted B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId)
END
GO