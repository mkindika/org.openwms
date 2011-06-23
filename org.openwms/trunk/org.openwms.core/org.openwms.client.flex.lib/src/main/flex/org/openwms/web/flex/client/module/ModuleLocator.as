/*
 * openwms.org, the Open Warehouse Management System.
 *
 * This file is part of openwms.org.
 *
 * openwms.org is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * openwms.org is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this software. If not, write to the Free
 * Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA, or see the FSF site: http://www.fsf.org.
 */
package org.openwms.web.flex.client.module {

    import flash.events.EventDispatcher;
    import flash.system.ApplicationDomain;

    import mx.collections.ArrayCollection;
    import mx.collections.XMLListCollection;
    import mx.controls.Alert;
    import mx.events.ModuleEvent;
    import mx.logging.ILogger;
    import mx.logging.Log;
    import mx.modules.IModuleInfo;
    import mx.modules.ModuleManager;

    import org.granite.reflect.Type;
    import org.granite.tide.ITideModule;
    import org.granite.tide.events.TideFaultEvent;
    import org.granite.tide.events.TideResultEvent;
    import org.granite.tide.spring.Context;
    import org.granite.tide.spring.Spring;
    import org.granite.tide.spring.Identity;

    import org.openwms.core.domain.Module;
    import org.openwms.web.flex.client.IApplicationModule;
    import org.openwms.web.flex.client.event.ApplicationEvent;
    import org.openwms.web.flex.client.model.ModelLocator;

    [Name]
    [ManagedEvent(name="MODULE_CONFIG_CHANGED")]
    [ManagedEvent(name="MODULES_CONFIGURED")]
    [ManagedEvent(name="MODULE_LOADED")]
    [ManagedEvent(name="MODULE_UNLOADED")]
    [ManagedEvent(name="APP.BEFORE_MODULE_UNLOAD")]
    [Bindable]
    /**
     * A ModuleLocator is the main implementation that cares about handling
     * with Flex Modules with the CORE Flex Application.
     * It is a Tide component and can be injected by name=moduleLocator.
     * It fires the following Tide Events:
     * MODULE_CONFIG_CHANGED, MODULES_CONFIGURED, MODULE_LOADED, MODULE_UNLOADED.
     *
     * @author <a href="mailto:scherrer@openwms.org">Heiko Scherrer</a>
     * @version $Revision$
     * @since 0.1
     */
    public class ModuleLocator extends EventDispatcher {

        [Inject]
        /**
         * Needs a Model to work on.
         */
        public var modelLocator : ModelLocator;
        [Inject]
        /**
         * Needs a TideContext.
         */
        public var tideContext : Context;
        [Inject]
        /**
         * Injected Tide identity object.
         */
        public var identity : Identity;

        private var toRemove : Module;
        private var _applicationDomain : ApplicationDomain = new ApplicationDomain(ApplicationDomain.currentDomain);
        private static var logger : ILogger = Log.getLogger("org.openwms.web.flex.client.module.ModuleLocator");

        /**
         * Simple constructor used by the Tide framework.
         */
        public function ModuleLocator() {
            Type.registerDomain(_applicationDomain);
        }

        [Observer("LOAD_ALL_MODULES")]
        /**
         * Usually this method is called when the application is initialized,
         * to load all modules and module configuration from the service.
         * After this startup configuration is read, the application can then
         * LOAD the swf modules.
         */
        public function loadModulesFromService() : void {
            trace("Loading all module definitions from the database");
            tideContext.moduleService.findAll(onModulesLoad, onFault);
        }

        [Observer("UNLOAD_ALL_MODULES")]
        /**
         * Is called when the UNLOAD_ALL_MODULES is fired to unload all Modules.
         * It iterates through the list of loadedModules and triggers unloading each of them.
         */
        public function unloadAllModules() : void {
            for (var url : String in modelLocator.loadedModules) {
                var module : Module = new Module();
                module.url = url;
                trace("Trigger unload for:" + url);
                beforeUnload(module);
            }
        }

        [Observer("SAVE_MODULE")]
        /**
         * Tries to save the module data via a service call.
         * Is called when the SAVE_MODULE event is fired.
         *
         * @param event An ApplicationEvent that holds the Module to be saved in its data field
         */
        public function saveModule(event : ApplicationEvent) : void {
            tideContext.moduleService.save(event.data as Module, onModuleSaved, onFault);
        }

        [Observer("DELETE_MODULE")]
        /**
         * Tries to remove the module data via a service call.
         * Is called when the DELETE_MODULE event is fired.
         *
         * @param event An ApplicationEvent that holds the Module to be removed in its data field
         */
        public function deleteModule(event : ApplicationEvent) : void {
            toRemove = event.data as Module;
            tideContext.moduleService.remove(event.data as Module, onModuleRemoved, onFault);
        }

        [Observer("SAVE_STARTUP_ORDERS")]
        /**
         * A collection of modules is passed to the service to save the startupOrder properties.
         * The startupOrders must be calculated and ordered before. Is called when the
         * SAVE_STARTUP_ORDERS event is fired.
         *
         * @param event An ApplicationEvent holds a list of Modules that shall be updated
         */
        public function saveStartupOrders(event : ApplicationEvent) : void {
            tideContext.moduleService.saveStartupOrder(event.data as ArrayCollection, onStartupOrdersSaved, onFault);
        }

        [Observer("LOAD_MODULE")]
        /**
         * Checks whether the module a registered Module and calls loadModule to load it.
         *
         * @param event An ApplicationEvent holds the Module to be loaded within the data property
         */
        public function onLoadModule(event : ApplicationEvent) : void {
            var module : Module = event.data as Module;
            if (module == null) {
                trace("Module instance is NULL, skip loading");
                return;
            }
            if (!isRegistered(module)) {
                trace("Module was not found in list of all modules");
                return;
            }
            loadModule(module);
        }

        [Observer("UNLOAD_MODULE")]
        /**
         * Checks whether the module a registered Module and calls unloadModule to unload it.
         *
         * @param event An ApplicationEvent holds the Module to be unloaded within the data property
         */
        public function onUnloadModule(event : ApplicationEvent) : void {
            var module : Module = event.data as Module;
            if (module == null) {
                trace("Module instance is NULL, skip unloading");
                return;
            }
            if (!isRegistered(module)) {
                trace("Module was not found in list of registered modules");
                return;
            }
            delete modelLocator.loadedModules[module.url];
            beforeUnload(module);
        }

        [Observer("APP.READY_TO_UNLOAD")]
        /**
         * Checks whether the module a registered Module and calls unloadModule to unload it.
         *
         * @param event An ApplicationEvent holds the Module to be unloaded within the data property
         */
        public function readyToUnload(event : ApplicationEvent) : void {
            trace("Got ready to unload event");
            var module : Module = event.data.module as Module;
            var mInf : IModuleInfo = event.data.mInf as IModuleInfo;
            var appModule : IApplicationModule = event.data.appModule as IApplicationModule;
            unloadModule(module, appModule, mInf);
        }

        /**
         * Returns an ArrayCollection of MenuItems of all loaded modules.
         *
         * @param stdItems A list of standard items that are included in the result list per default
         */
        public function getActiveMenuItems(stdItems : XMLListCollection=null) : XMLListCollection {
            var all : XMLListCollection = new XMLListCollection();
            if (stdItems != null) {
                for each (var stdNode : XML in stdItems) {
                    all.addItem(stdNode);
                }
            }
            for each (var module : Module in modelLocator.allModules) {
                if (modelLocator.loadedModules[module.url] != null) {
                    // Get an handle to IApplicationModule here to retrieve the list of items
                    // not like it is here to get the info from the db
                    var mInf : IModuleInfo = modelLocator.loadedModules[module.url] as IModuleInfo;
                    var appModule : Object = mInf.factory.create();
                    if (appModule is IApplicationModule) {
                        var tree : XMLListCollection = appModule.getMainMenuItems();
                        // TODO: In Flex 3.5 replace with addAll()
                        //all.addAll(tree);
                        for each (var node : XML in tree) {
                            all.addItem(node);
                        }
                    }
                }
            }
            return all;
        }

        /**
         * Check whether the module is in the list of persistend modules.
         *
         * @param module The Module to be checked
         * @return <code>true</code> when the module is known, otherwise <code>false</code>
         */
        public function isRegistered(module : Module) : Boolean {
            if (module == null) {
                return false;
            }
            for each (var m : Module in modelLocator.allModules) {
                if (m.moduleName == module.moduleName) {
                    return true;
                }
            }
            return false;
        }

        /**
         * Checks whether a module as loaded before.
         *
         * @param moduleName The name of the Module to check
         * @return <code>true</code> if the module was loaded, otherwise <code>false</code>.
         */
        public function isLoaded(moduleName : String) : Boolean {
            if (moduleName == null) {
                return false;
            }
            for each (var url : String in modelLocator.loadedModules) {
                if ((modelLocator.loadedModules[url].data as Module).moduleName == moduleName) {
                    return true;
                }
            }
            return false;
        }

        // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        //
        // privates
        //
        // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

        /**
         * Callback function when module configuration is retrieved from the service.
         * The configuration is stored in allModules and the model is set to initialized.
         */
        private function onModulesLoad(event : TideResultEvent) : void {
            modelLocator.allModules = event.result as ArrayCollection;
            modelLocator.isInitialized = true;
            startAllModules();
        }

        /**
         * Callback when startupOrder was saved for a list of modules.
         */
        private function onStartupOrdersSaved(event : TideResultEvent) : void {
            // We do not need to update the list of modules here, keep quite
        }

        /**
         * This function checks all known modules if they are configured to be loaded
         * on startup and tries to start each Module if it hasn't been loaded so far.
         */
        private function startAllModules() : void {
            var noModulesLoaded : Boolean = true;
            for each (var module : Module in modelLocator.allModules) {
                if (module.loadOnStartup) {
                    noModulesLoaded = false;
                    if (modelLocator.loadedModules[module.url] != null) {
                        module.loaded = true;
                        continue;
                    }
                    trace("Trying to load module : " + module.url);
                    loadModule(module);
                } else {
                    logger.debug("Module not set to be loaded on startup : " + module.moduleName);
                }
            }
            if (noModulesLoaded) {
                dispatchEvent(new ApplicationEvent(ApplicationEvent.MODULES_CONFIGURED));
            }
        }

        private function loadModule(module : Module) : void {
            var mInf : IModuleInfo = ModuleManager.getModule(module.url);
            if (mInf != null) {
                if (mInf.loaded) {
                    module.loaded = true;
                    trace("Module was already loaded : " + module.moduleName);
                    return;
                } else {
                    mInf.addEventListener(ModuleEvent.READY, onModuleLoaded, false, 0, false);
                    mInf.addEventListener(ModuleEvent.ERROR, onModuleLoaderError);
                    mInf.data = module;
                    trace("Putting in loadedModules:" + module.url);
                    modelLocator.loadedModules[module.url] = mInf;
                    mInf.load(_applicationDomain);
                    return;
                }
            }
            trace("No module to load with url: " + module.url);
        }

        private function beforeUnload(module : Module) : void {
            var mInf : IModuleInfo = ModuleManager.getModule(module.url);
            trace("testL:" + modelLocator.loadedModules.hasOwnProperty(module.url));
            trace("Before unloading of module:" + module.url);
            var appModule : IApplicationModule = mInf.factory.create() as IApplicationModule;
            fireBeforeUnloadEvent(appModule, mInf, module);
            return;
        }

        private function unloadModule(module : Module, appModule : IApplicationModule, mInf : IModuleInfo) : void {
            if (!modelLocator.unloadedModules.hasOwnProperty(module.url)) {
                mInf.addEventListener(ModuleEvent.UNLOAD, onModuleUnloaded);
                mInf.addEventListener(ModuleEvent.ERROR, onModuleLoaderError);
                mInf.data = module;
                modelLocator.unloadedModules[module.url] = mInf;
                Spring.getInstance().removeModule(Object(appModule).constructor as Class)
                appModule.destroyModule();
                mInf.unload();
                mInf.release();
                return;
            } else {
                logger.debug("Module was not loaded before, nothing to unload");
            }
        }

        /**
         * When module data was saved successfully it is updated in the list of modules
         * and set as actual selected module.
         */
        private function onModuleSaved(event : TideResultEvent) : void {
            addModule(event.result as Module);
            modelLocator.selectedModule = event.result as Module;
        }

        /**
         * When module data was removed successfully it is updated in the list of modules
         * and unset as selected module.
         */
        private function onModuleRemoved(event : TideResultEvent) : void {
            removeFromModules(toRemove);
            toRemove = null;
        }

        /**
         * Fire an event to notify others that configuration data of a module has changed.
         * The event data (e.data) contains the changed module.
         */
        private function fireChangedEvent(module : IApplicationModule) : void {
            var e : ApplicationEvent = new ApplicationEvent(ApplicationEvent.MODULE_CONFIG_CHANGED);
            e.data = module;
            dispatchEvent(e);
        }

        private function fireBeforeUnloadEvent(appModule : IApplicationModule, mInf : IModuleInfo, module : Module) : void {
            var e : ApplicationEvent = new ApplicationEvent(ApplicationEvent.BEFORE_MODULE_UNLOAD);
            e.data = {appModule: appModule, mInf: mInf, module: module};
            dispatchEvent(e);
        }

        /**
         * This method is called when an application module was successfully loaded.
         * Loading a module can be triggered by the Module Management screen or at application
         * startup if the module is configured to behave so.
         */
        private function onModuleLoaded(e : ModuleEvent) : void {
            trace("Successfully loaded module: " + e.module.url);
            var module : Module = (e.module.data as Module);
            module.loaded = true;
            if (modelLocator.loadedModules[module.url] == null) {
                modelLocator.loadedModules[module.url] = ModuleManager.getModule(module.url);
            }
            delete modelLocator.unloadedModules[module.url];
            var appModule : Object = e.module.factory.create();
            if (appModule is IApplicationModule) {
                trace("Adding appModule to core Spring context+++" + (Object(appModule).constructor as Class));
                Spring.getInstance().addModule(Object(appModule).constructor as Class, _applicationDomain);
                appModule.start(_applicationDomain);
                fireLoadedEvent(appModule as IApplicationModule);
            } else {
                trace("Module that was loaded is not an IApplicationModule");
            }
            var mInf : IModuleInfo = modelLocator.loadedModules[module.url] as IModuleInfo;
            mInf.removeEventListener(ModuleEvent.READY, onModuleLoaded);
            mInf.removeEventListener(ModuleEvent.ERROR, onModuleLoaderError);
        }

        /**
         * This method is called when an application module was successfully unloaded. Unloading
         * a module is usually triggered by the Module Management screen. As a result an event is
         * fired to inform the main application about the unload. For instance the main application
         * could rebuild the menu bar.
         */
        private function onModuleUnloaded(e : ModuleEvent) : void {
            trace("Successfully hard-unloaded Module with URL : " + e.module.url);
            var module : Module = (e.module.data as Module);
            module.loaded = false;
            if (modelLocator.unloadedModules[module.url] == null) {
                modelLocator.unloadedModules[module.url] == ModuleManager.getModule(module.url);
            }
            delete modelLocator.loadedModules[module.url];
            var appModule : Object = e.module.factory.create();
            if (appModule is IApplicationModule) {
                fireUnloadedEvent(appModule as IApplicationModule);
            } else {
                trace("Module that was unloaded is not an IApplicationModule");
            }
            var mInf : IModuleInfo = modelLocator.unloadedModules[module.url] as IModuleInfo;
            mInf.removeEventListener(ModuleEvent.UNLOAD, onModuleUnloaded);
            mInf.removeEventListener(ModuleEvent.ERROR, onModuleLoaderError);
        }

        /**
         * Fire an event to notify others that a module was successfully unloaded.
         * The event data (e.data) contains the module that was loaded.
         */
        private function fireLoadedEvent(module : IApplicationModule) : void {
            var e : ApplicationEvent = new ApplicationEvent(ApplicationEvent.MODULE_LOADED);
            e.data = module;
            dispatchEvent(e);
        }

        /**
         * Fire an event to notify others that a module was successfully unloaded.
         * The event data (e.data) contains the module that was unloaded.
         */
        private function fireUnloadedEvent(module : IApplicationModule) : void {
            var e : ApplicationEvent = new ApplicationEvent(ApplicationEvent.MODULE_UNLOADED);
            e.data = module;
            dispatchEvent(e);
        }

        /**
         * This method is called when an error occurred while loading or unloading a module.
         */
        private function onModuleLoaderError(e : ModuleEvent) : void {
            if (e.module != null) {
                trace("Loading/Unloading a module [" + e.module.url + "] failed with error : " + e.errorText);
                if (e.module.data != null) {
                    var module : Module = (e.module.data as Module);
                    module.loaded = false;
                    var mInf : IModuleInfo = modelLocator.loadedModules[module.url] as IModuleInfo;
                    if (mInf != null) {
                        // TODO: Also remove other listeners here
                        mInf.removeEventListener(ModuleEvent.ERROR, onModuleLoaderError);
                        modelLocator.unloadedModules[module.url] = mInf;
                    }
                    delete modelLocator.loadedModules[module.url];
                }
                Alert.show("Loading/Unloading a module [" + e.module.url + "] failed with error : " + e.errorText);
            } else {
                trace("Loading/Unloading a module failed, no further module data available here");
                Alert.show("Loading/Unloading a module failed, no further module data available here");
            }
        }

        /**
         * Add a module to the list of all modules.
         */
        private function addModule(module : Module) : void {
            if (module == null) {
                return;
            }
            var found : Boolean = false;
            for each (var m : Module in modelLocator.allModules) {
                if (m.moduleName == module.moduleName) {
                    found = true;
                    m = module;
                }
            }
            if (!found) {
                modelLocator.allModules.addItem(module);
            }
            if (modelLocator.loadedModules[module.url] != null) {
                modelLocator.loadedModules[module.url] = ModuleManager.getModule(module.url);
            }
            if (modelLocator.unloadedModules[module.url] != null) {
                modelLocator.unloadedModules[module.url] = ModuleManager.getModule(module.url);
            }
        }

        /**
         * Removes a module from the list of all modules and unloads it in the case it was loaded before.
         */
        private function removeFromModules(module : Module, unload : Boolean=false) : Boolean {
            if (module == null) {
                return false;
            }
            var modules : Array = modelLocator.allModules.toArray();
            for (var i : int = 0; i < modules.length; i++) {
                if (modules[i].moduleName == module.moduleName) {
                    modelLocator.allModules.removeItemAt(i);
                    if (unload) {
                        var mInfo : IModuleInfo = ModuleManager.getModule(module.url);
                        mInfo.addEventListener(ModuleEvent.READY, onModuleLoaded);
                        mInfo.addEventListener(ModuleEvent.ERROR, onModuleLoaderError);
                        if (mInfo != null && mInfo.loaded) {
                            mInfo.data = module;
                            mInfo.unload();
                        }
                    }
                    return true;
                }
            }
            return false;
        }

        private function onFault(event : TideFaultEvent) : void {
            trace("Error executing operation on ModuleManagement service:" + event.fault);
            Alert.show("Error executing operation on ModuleManagement service" + event.fault);
        }

    }
}

