//-------------------------------------------------------------------------------
// <copyright file="ScopingHandlerDecorator.cs" company="Appccelerate">
//   Copyright (c) 2008-2012
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
// </copyright>
//-------------------------------------------------------------------------------

namespace Appccelerate.ScopingEventBroker
{
    using System;
    using System.Reflection;
    using Appccelerate.EventBroker;

    public class ScopingHandlerDecorator : IHandler
    {
        private readonly IHandler handler;
        private readonly IEventScopeHolder scopeHolder;

        public ScopingHandlerDecorator(IHandler handler, IEventScopeHolder scopeHolder)
        {
            this.scopeHolder = scopeHolder;
            this.handler = handler;
        }

        public HandlerKind Kind
        {
            get { return this.handler.Kind; }
        }

        public void Initialize(object subscriber, MethodInfo handlerMethod, IExtensionHost extensionHost)
        {
            this.handler.Initialize(subscriber, handlerMethod, extensionHost);
        }

        public void Handle(IEventTopic eventTopic, object sender, EventArgs e, Delegate subscriptionHandler)
        {
            IEventScopeRegisterer scope = this.scopeHolder.Current;

            if (scope != null)
            {
                scope.Register(() => this.handler.Handle(eventTopic, sender, e, subscriptionHandler));
            }
            else
            {
                this.handler.Handle(eventTopic, sender, e, subscriptionHandler);
            }
        }
    }
}