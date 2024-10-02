﻿CREATE VIEW dbo.Resource
AS
SELECT ResourceTypeId
      ,ResourceSurrogateId
      ,ResourceId
      ,Version
      ,IsHistory
      ,IsDeleted
      ,RequestMethod
      ,RawResource
      ,IsRawResourceMetaSet
      ,SearchParamHash
      ,TransactionId
      ,HistoryTransactionId
  FROM dbo.ResourceHistory
UNION ALL
SELECT ResourceTypeId
      ,ResourceSurrogateId
      ,ResourceId
      ,Version
      ,IsHistory
      ,IsDeleted
      ,RequestMethod
      ,RawResource
      ,IsRawResourceMetaSet
      ,SearchParamHash
      ,TransactionId
      ,NULL
  FROM dbo.ResourceCurrent
GO
CREATE TRIGGER dbo.ResourceIns ON dbo.Resource INSTEAD OF INSERT
AS
BEGIN
  INSERT INTO dbo.RawResources
      (
          ResourceTypeId
         ,ResourceSurrogateId
         ,RawResource
      )
    SELECT ResourceTypeId
          ,ResourceSurrogateId
          ,RawResource
      FROM Inserted

  INSERT INTO dbo.ResourceCurrentTbl
      (
           ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
      )
    SELECT ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
      FROM Inserted
      WHERE IsHistory = 0

  INSERT INTO dbo.ResourceHistoryTbl
      (
           ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
      )
    SELECT ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
      FROM Inserted
      WHERE IsHistory = 1
END
GO
CREATE TRIGGER dbo.ResourceUpd ON dbo.Resource INSTEAD OF UPDATE
AS
BEGIN
  IF UPDATE(SearchParamHash) AND NOT UPDATE(IsHistory)
  BEGIN
    UPDATE B
      SET SearchParamHash = A.SearchParamHash -- this is the only update we support
      FROM Inserted A
           JOIN dbo.ResourceCurrentTbl B ON B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId
      WHERE A.IsHistory = 0
    
    RETURN
  END

  IF NOT UPDATE(IsHistory)
    RAISERROR('Generic updates are not supported via Resource view',18,127)

  DELETE FROM A
    FROM dbo.ResourceCurrentTbl A
    WHERE EXISTS (SELECT * FROM Inserted B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId AND B.IsHistory = 1)

  INSERT INTO dbo.ResourceHistoryTbl
      (
           ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
      )
    SELECT ResourceTypeId
          ,ResourceSurrogateId
          ,ResourceId
          ,Version
          ,IsDeleted
          ,RequestMethod
          --,RawResource
          ,IsRawResourceMetaSet
          ,SearchParamHash
          ,TransactionId
          ,HistoryTransactionId
      FROM Inserted
      WHERE IsHistory = 1
END
GO
CREATE TRIGGER dbo.ResourceDel ON dbo.Resource INSTEAD OF DELETE
AS
BEGIN
  DELETE FROM A
    FROM dbo.ResourceCurrentTbl A
    WHERE EXISTS (SELECT * FROM Deleted B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId AND B.IsHistory = 0)

  DELETE FROM A
    FROM dbo.ResourceHistoryTbl A
    WHERE EXISTS (SELECT * FROM Deleted B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId AND B.IsHistory = 1)

  DELETE FROM A
    FROM dbo.RawResources A
    WHERE EXISTS (SELECT * FROM Deleted B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId)
      AND NOT EXISTS (SELECT * FROM Resource B WHERE B.ResourceTypeId = A.ResourceTypeId AND B.ResourceSurrogateId = A.ResourceSurrogateId) 
END
GO
