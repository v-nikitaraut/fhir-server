﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using MediatR;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Health.Extensions.DependencyInjection;
using Microsoft.Health.Fhir.Api.Features.ApiNotifications;
using Microsoft.Health.Fhir.Core.Features.Operations.Export;
using Microsoft.Health.Fhir.CosmosDb.Features.Metrics;

namespace Microsoft.Health.Fhir.Shared.Tests.E2E.Rest.Metric
{
    [RequiresIsolatedDatabase]
    public class StartupWithMetricHandler : StartupBaseForCustomProviders
    {
        public StartupWithMetricHandler(IConfiguration configuration)
            : base(configuration)
        {
        }

        [System.Obsolete]
#pragma warning disable CS0809 // Obsolete member overrides non-obsolete member
        public override void ConfigureServices(IServiceCollection services)
#pragma warning restore CS0809 // Obsolete member overrides non-obsolete member
        {
            base.ConfigureServices(services);

            services.Add<MetricHandler>()
                .Singleton()
                .AsService<INotificationHandler<ApiResponseNotification>>()
                .AsService<INotificationHandler<CosmosStorageRequestMetricsNotification>>()
                .AsService<INotificationHandler<ExportTaskMetricsNotification>>();
        }
    }
}
