mkdir -p bin
project_name="app"

odin build src -out:bin/${project_name}
if [ $? -ne 0 ]; then
    echo "Build failed."
    exit 1
fi

# shellcheck disable=SC2164
cd bin 
./${project_name}
