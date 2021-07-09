﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Hl7.Fhir.Model;

namespace Microsoft.Health.Fhir.Client
{
    public static class FhirClientExtensions
    {
        public static async Task<TResource[]> CreateResourcesAsync<TResource>(this FhirClient client, int count, string tag)
            where TResource : Resource, new()
        {
            TResource[] resources = new TResource[count];

            for (int i = 0; i < resources.Length; i++)
            {
                TResource resource = new TResource();
                resource.Meta = new Meta()
                {
                    Tag = new List<Coding>
                    {
                        new Coding("testTag", tag),
                    },
                };

                using var response = await client.CreateAsync(resource);
                resources[i] = response;
            }

            return resources;
        }

        public static async Task<TResource> CreateResourcesAsync<TResource>(this FhirClient client, Func<TResource> resourceFactory)
            where TResource : Resource
        {
            TResource resource = resourceFactory();

            return await client.CreateAsync(resource);
        }

        public static async Task<TResource[]> CreateResourcesAsync<TResource>(this FhirClient client, params Action<TResource>[] resourceCustomizer)
            where TResource : Resource, new()
        {
            TResource[] resources = new TResource[resourceCustomizer.Length];

            for (int i = 0; i < resources.Length; i++)
            {
                TResource resource = new TResource();

                resourceCustomizer[i](resource);
                using var response = await client.CreateAsync(resource);
                resources[i] = response;
            }

            return resources;
        }

        /// <summary>
        /// Performs a create by calling <see cref="FhirClient.UpdateAsync{T}(T,string,System.Threading.CancellationToken)"/>, by assigning a new GUID to the Id property.
        /// This is sometimes desirable over calling <see cref="FhirClient.CreateAsync{T}(T,string,System.Threading.CancellationToken)"/> when you want to be sure that at most
        /// one resource is created, even if the call has to be issued multiple times.
        /// </summary>
#pragma warning disable SA1618 // Generic type parameters should be documented
#pragma warning disable SA1611 // Element parameters should be documented
        public static Task<FhirResponse<T>> CreateByUpdateAsync<T>(this FhirClient client, T resource, CancellationToken cancellationToken = default)
#pragma warning restore SA1611 // Element parameters should be documented
#pragma warning restore SA1618 // Generic type parameters should be documented
            where T : Resource
        {
            resource.Id = Guid.NewGuid().ToString();

            return client.UpdateAsync(resource, cancellationToken: cancellationToken);
        }
    }
}
