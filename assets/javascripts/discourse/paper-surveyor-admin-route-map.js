export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("paper-surveyor", { path: "paper-surveyor" });
  },
};
