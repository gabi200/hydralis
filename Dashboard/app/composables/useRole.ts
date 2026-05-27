export type UserRole = "dispatcher" | "industrial" | "gas" | "admin";

export const useRole = () => {
  const currentRole = useState<UserRole>("user-role", () => "dispatcher");

  const setRole = (role: UserRole) => {
    currentRole.value = role;
  };

  const isDispatcher = computed(() => currentRole.value === "dispatcher");
  const isIndustrial = computed(() => currentRole.value === "industrial");
  const isGas = computed(() => currentRole.value === "gas");
  const isAdmin = computed(() => currentRole.value === "admin");

  const roleLabel = computed(() => {
    switch (currentRole.value) {
      case "dispatcher":
        return "Dispatcher";
      case "industrial":
        return "Industrial";
      case "gas":
        return "Gas Operator";
      case "admin":
        return "Administrator";
    }
  });

  const roleIcon = computed(() => {
    switch (currentRole.value) {
      case "dispatcher":
        return "mdi:shield-alert";
      case "industrial":
        return "mdi:factory";
      case "gas":
        return "mdi:gas-cylinder";
      case "admin":
        return "mdi:cog";
    }
  });

  return {
    currentRole,
    setRole,
    isDispatcher,
    isIndustrial,
    isGas,
    isAdmin,
    roleLabel,
    roleIcon,
  };
};
