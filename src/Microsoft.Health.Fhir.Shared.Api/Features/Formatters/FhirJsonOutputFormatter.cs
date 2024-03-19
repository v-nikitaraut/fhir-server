﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using EnsureThat;
using Hl7.Fhir.Model;
using Hl7.Fhir.Serialization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Formatters;
using Microsoft.Health.Fhir.Api.Features.ContentTypes;
using Microsoft.Health.Fhir.Api.Features.Resources.Bundle;
using Microsoft.Health.Fhir.Core.Extensions;
using Microsoft.Health.Fhir.Core.Features.Persistence;
using Microsoft.Health.Fhir.Core.Models;
using Microsoft.Health.Fhir.Shared.Core.Features.Search;
using Newtonsoft.Json;
using Task = System.Threading.Tasks.Task;

namespace Microsoft.Health.Fhir.Api.Features.Formatters
{
    internal class FhirJsonOutputFormatter : TextOutputFormatter
    {
        private readonly FhirJsonSerializer _fhirJsonSerializer;
        private readonly ResourceDeserializer _deserializer;
        private readonly IArrayPool<char> _charPool;
        private readonly IModelInfoProvider _modelInfoProvider;

        public FhirJsonOutputFormatter(
            FhirJsonSerializer fhirJsonSerializer,
            ResourceDeserializer deserializer,
            ArrayPool<char> charPool,
            IModelInfoProvider modelInfoProvider)
        {
            EnsureArg.IsNotNull(fhirJsonSerializer, nameof(fhirJsonSerializer));
            EnsureArg.IsNotNull(deserializer, nameof(deserializer));
            EnsureArg.IsNotNull(charPool, nameof(charPool));
            EnsureArg.IsNotNull(modelInfoProvider, nameof(modelInfoProvider));

            _fhirJsonSerializer = fhirJsonSerializer;
            _deserializer = deserializer;
            _charPool = new JsonArrayPool(charPool);
            _modelInfoProvider = modelInfoProvider;

            SupportedEncodings.Add(Encoding.UTF8);
            SupportedEncodings.Add(Encoding.Unicode);
            SupportedMediaTypes.Add(KnownContentTypes.JsonContentType);
            SupportedMediaTypes.Add(KnownMediaTypeHeaderValues.ApplicationJson);
            SupportedMediaTypes.Add(KnownMediaTypeHeaderValues.TextJson);
            SupportedMediaTypes.Add(KnownMediaTypeHeaderValues.ApplicationAnyJsonSyntax);
        }

        protected override bool CanWriteType(Type type)
        {
            EnsureArg.IsNotNull(type, nameof(type));

            return typeof(Resource).IsAssignableFrom(type) || typeof(RawResourceElement).IsAssignableFrom(type);
        }

        public override async Task WriteResponseBodyAsync(OutputFormatterWriteContext context, Encoding selectedEncoding)
        {
            EnsureArg.IsNotNull(context, nameof(context));
            EnsureArg.IsNotNull(selectedEncoding, nameof(selectedEncoding));

            HttpResponse response = context.HttpContext.Response;

            var elementsSearchParameter = context.HttpContext.GetElementsOrDefault();
            var summarySearchParameter = context.HttpContext.GetSummaryTypeOrDefault();
            var pretty = context.HttpContext.GetPrettyOrDefault();
            var hasElements = elementsSearchParameter?.Any() == true;
            Resource resource = null;
            var summaryProvider = _modelInfoProvider.StructureDefinitionSummaryProvider;
            var additionalElements = new HashSet<string>();

            if (context.Object is Hl7.Fhir.Model.Bundle)
            {
                var bundle = context.Object as Hl7.Fhir.Model.Bundle;
                resource = bundle;

                if (hasElements ||
                    summarySearchParameter != Hl7.Fhir.Rest.SummaryType.False ||
                    !bundle.Entry.All(x => x is RawBundleEntryComponent))
                {
                    // _elements is not supported for a raw resource, revert to using FhirJsonSerializer
                    foreach (var rawBundleEntryComponent in bundle.Entry)
                    {
                        if (rawBundleEntryComponent is RawBundleEntryComponent { ResourceElement: not null } entry)
                        {
                            Resource poco = entry.ResourceElement.ToPoco<Resource>(_deserializer);
                            if (poco.TypeName == KnownResourceTypes.OperationOutcome)
                            {
                                rawBundleEntryComponent.Response.Outcome = poco;
                            }
                            else
                            {
                                rawBundleEntryComponent.Resource = poco;
                            }

                            if (hasElements)
                            {
                                var typeinfo = summaryProvider.Provide(rawBundleEntryComponent.Resource.TypeName);
                                var required = typeinfo.GetElements().Where(e => e.IsRequired).ToList();
                                additionalElements.UnionWith(required.Select(x => x.ElementName));
                            }
                        }
                    }
                }
                else
                {
                    await BundleSerializer.Serialize(context.Object as Hl7.Fhir.Model.Bundle, context.HttpContext.Response.Body, pretty);
                    return;
                }
            }
            else if (context.Object is RawResourceElement)
            {
                if (hasElements ||
                    summarySearchParameter != Hl7.Fhir.Rest.SummaryType.False)
                {
                    // _elements is not supported for a raw resource, revert to using FhirJsonSerializer
                    resource = ((RawResourceElement)context.Object).ToPoco<Resource>(_deserializer);
                    if (hasElements)
                    {
                        var typeinfo = summaryProvider.Provide(resource.TypeName);
                        var required = typeinfo.GetElements().Where(e => e.IsRequired).ToList();
                        additionalElements.UnionWith(required.Select(x => x.ElementName));
                    }
                }
                else
                {
                    await ((RawResourceElement)context.Object).SerializeToStreamAsUtf8Json(context.HttpContext.Response.Body, pretty);
                    return;
                }
            }
            else
            {
                resource = (Resource)context.Object;
                if (hasElements)
                {
                    var typeinfo = summaryProvider.Provide(resource.TypeName);
                    var required = typeinfo.GetElements().Where(e => e.IsRequired).ToList();
                    additionalElements.UnionWith(required.Select(x => x.ElementName));
                }
            }

            if (hasElements)
            {
                additionalElements.UnionWith(elementsSearchParameter);
                additionalElements.Add("meta");
            }

            await using TextWriter textWriter = context.WriterFactory(response.Body, selectedEncoding);
            await using var jsonWriter = new JsonTextWriter(textWriter);
            jsonWriter.ArrayPool = _charPool;

            if (pretty)
            {
                jsonWriter.Formatting = Formatting.Indented;
            }

            await _fhirJsonSerializer.SerializeAsync(resource, jsonWriter, summarySearchParameter, hasElements ? additionalElements.ToArray() : null);
            await jsonWriter.FlushAsync();
        }
    }
}
