package migration_test

import (
	"database/sql"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

const preMigrationVersion = 1515427936
const postMigrationVersion = 1515427942

type jobCombination struct {
	id               int
	jobID            int
	combination      string
	inputsDetermined bool
}

var _ = Describe("Populate job combinations", func() {
	var (
		db *sql.DB
	)

	Context("Down", func() {
		It("truncates all job combinations", func() {
			db = postgresRunner.OpenDBAtVersion(postMigrationVersion)

			setupTeamAndPipeline(db)

			_, err := db.Exec(`
				INSERT INTO jobs(id, pipeline_id, name, config, inputs_determined) VALUES
					(1, 1, 'a-job', '{"name":"a-job"}', true)
			`)
			Expect(err).NotTo(HaveOccurred())

			_, err = db.Exec(`
					INSERT INTO job_combinations(id, job_id, combination, inputs_determined) VALUES
						(1, 1, '{}', true)
				`)
			Expect(err).NotTo(HaveOccurred())

			_ = db.Close()

			db = postgresRunner.OpenDBAtVersion(preMigrationVersion)

			var jobCombinationCount int
			err = db.QueryRow(`
				SELECT COUNT(1) FROM job_combinations
			`).Scan(&jobCombinationCount)
			Expect(err).NotTo(HaveOccurred())
			Expect(jobCombinationCount).To(Equal(0))

			_ = db.Close()
		})
	})

	Context("Up", func() {
		It("creates a job combination for each active job", func() {
			db = postgresRunner.OpenDBAtVersion(preMigrationVersion)

			setupTeamAndPipeline(db)

			_, err := db.Exec(`
				INSERT INTO jobs(id, pipeline_id, name, config, inputs_determined, active) VALUES
					(1, 1, 'a-job', '{"name":"a-job"}', true, true),
					(2, 1, 'some-job', '{"name":"some-job","plan":[{"get":"some-resource"}]}', true, true),
					(3, 1, 'other-job', '{"name":"other-job","plan":[{"get":"some-resource"},{"put":"other-resource"}]}', false, true),
					(4, 1, 'another-job', '{"name":"another-job"}', true, false)
			`)
			Expect(err).NotTo(HaveOccurred())

			_ = db.Close()

			db = postgresRunner.OpenDBAtVersion(postMigrationVersion)

			rows, err := db.Query(`
				SELECT id, job_id, combination, inputs_determined FROM job_combinations
			`)
			Expect(err).NotTo(HaveOccurred())

			jobCombinations := []jobCombination{}

			for rows.Next() {
				var combination sql.NullString

				jc := jobCombination{}

				err := rows.Scan(&jc.id, &jc.jobID, &combination, &jc.inputsDetermined)
				Expect(err).NotTo(HaveOccurred())
				Expect(combination.Valid).To(BeTrue())

				jc.combination = string(combination.String)
				jobCombinations = append(jobCombinations, jc)
			}

			_ = db.Close()

			Expect(len(jobCombinations)).To(Equal(3))
			Expect(jobCombinations[0].id).To(Equal(1))
			Expect(jobCombinations[1].id).To(Equal(2))
			Expect(jobCombinations[2].id).To(Equal(3))
			Expect(jobCombinations[0].jobID).To(Equal(1))
			Expect(jobCombinations[1].jobID).To(Equal(2))
			Expect(jobCombinations[2].jobID).To(Equal(3))
			Expect(jobCombinations[0].combination).To(Equal(`{}`))
			Expect(jobCombinations[1].combination).To(Equal(`{"some-resource": "default"}`))
			Expect(jobCombinations[2].combination).To(Equal(`{"some-resource": "default", "other-resource": "default"}`))
			Expect(jobCombinations[0].inputsDetermined).To(Equal(true))
			Expect(jobCombinations[1].inputsDetermined).To(Equal(true))
			Expect(jobCombinations[2].inputsDetermined).To(Equal(false))
		})
	})
})

func setupTeamAndPipeline(db *sql.DB) {
	_, err := db.Exec(`
				INSERT INTO teams(id, name) VALUES
					(1, 'some-team')
			`)
	Expect(err).NotTo(HaveOccurred())

	_, err = db.Exec(`
				INSERT INTO pipelines(id, team_id, name) VALUES
					(1, 1, 'some-team')
			`)
	Expect(err).NotTo(HaveOccurred())
}
