import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "paper-surveyor";

export default {
  name: "paper-surveyor-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "flask");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "paper_surveyor.title",
          route: "adminPlugins.show.paper-surveyor",
        },
      ]);
    });
  },
};
