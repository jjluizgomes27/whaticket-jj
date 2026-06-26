import { QueryInterface, DataTypes, Sequelize } from "sequelize";

module.exports = {
  up: async (queryInterface: QueryInterface) => {
    const dialect = queryInterface.sequelize.getDialect();

    await queryInterface.addColumn("Tickets", "uuid", {
      type: DataTypes.UUID,
      allowNull: true,
      defaultValue: dialect === "postgres" ? Sequelize.literal('uuid_generate_v4()') : null
    });
  },

  down: async (queryInterface: QueryInterface) => {
    await queryInterface.removeColumn("Tickets", "uuid");
  }
};
