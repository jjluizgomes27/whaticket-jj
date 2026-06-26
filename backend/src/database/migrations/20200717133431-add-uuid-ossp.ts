import { QueryInterface } from "sequelize";

module.exports = {
  up: async (queryInterface: QueryInterface) => {
    const dialect = queryInterface.sequelize.getDialect();

    // uuid-ossp é uma extensão exclusiva do PostgreSQL.
    // Em MySQL/MariaDB esta migration deve ser ignorada.
    if (dialect === "postgres") {
      await queryInterface.sequelize.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
    }
  },

  down: async (queryInterface: QueryInterface) => {
    const dialect = queryInterface.sequelize.getDialect();

    if (dialect === "postgres") {
      await queryInterface.sequelize.query('DROP EXTENSION IF EXISTS "uuid-ossp"');
    }
  }
};
