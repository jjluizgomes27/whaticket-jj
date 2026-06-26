import { QueryInterface, DataTypes, Sequelize } from "sequelize";

module.exports = {
  up: async (queryInterface: QueryInterface) => {
    const dialect = queryInterface.sequelize.getDialect();
    const defaultValue = dialect === "postgres"
      ? Sequelize.literal('uuid_generate_v4()')
      : Sequelize.literal('(UUID())');

    await queryInterface.addColumn("Tickets", "uuid", {
      type: DataTypes.UUID,
      allowNull: true,
      defaultValue
    });
  },

  down: async (queryInterface: QueryInterface) => {
    await queryInterface.removeColumn("Tickets", "uuid");
  }
};
