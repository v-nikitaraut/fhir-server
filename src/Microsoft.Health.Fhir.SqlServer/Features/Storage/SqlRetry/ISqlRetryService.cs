﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace Microsoft.Health.Fhir.SqlServer.Features.Storage
{
    public interface ISqlRetryService
    {
        string Database { get; }

        Task TryLogEvent(string process, string status, string text, DateTime? startDate, CancellationToken cancellationToken);

        Task ExecuteSql<TLogger>(Func<SqlConnection, CancellationToken, SqlException, Task> action, ILogger<TLogger> logger, CancellationToken cancellationToken, bool isReadOnly = false, string warehouseConnectionString = null);

        Task ExecuteSql<TLogger>(SqlCommand sqlCommand, Func<SqlCommand, CancellationToken, Task> action, ILogger<TLogger> logger, string logMessage, CancellationToken cancellationToken, bool isReadOnly = false, bool disableRetries = false);

        Task<IReadOnlyList<TResult>> ExecuteReaderAsync<TResult, TLogger>(SqlCommand sqlCommand, Func<SqlDataReader, TResult> readerToResult, ILogger<TLogger> logger, string logMessage, CancellationToken cancellationToken, bool isReadOnly = false);
    }
}
