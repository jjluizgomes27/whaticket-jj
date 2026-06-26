import { QueryInterface, DataTypes } from "sequelize";

module.exports = {
  up: async (queryInterface: QueryInterface) => {
    const dialect = queryInterface.sequelize.getDialect();
    const schedulesType = dialect === "postgres" ? DataTypes.JSONB : DataTypes.JSON;

    await queryInterface.addColumn("Companies", "status", {
      type: DataTypes.BOOLEAN,
      defaultValue: true
    });

    await queryInterface.addColumn("Companies", "schedules", {
      type: schedulesType,
      allowNull: true
    });
  },

  down: async (queryInterface: QueryInterface) => {
    await queryInterface.removeColumn("Companies", "schedules");
    await queryInterface.removeColumn("Companies", "status");
  }
};
