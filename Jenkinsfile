pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                echo 'Building..'
		sh 'swift build -c release'
		
            }
        }
    }
}