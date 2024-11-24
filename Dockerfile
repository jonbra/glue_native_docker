# Use Ubuntu as the base image
FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV GLUE_HOME=/opt/gluetools
ENV PATH=${PATH}:${GLUE_HOME}/bin

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    openjdk-8-jdk \
    mysql-server \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download and install GLUE
RUN mkdir -p ${GLUE_HOME} \
    && wget -O gluetools.zip http://glue-tools.cvr.gla.ac.uk/downloads/glueInstallDir-1.1.113.zip \
    && unzip -d ${GLUE_HOME} gluetools.zip \
    && mv ${GLUE_HOME}/gluetools/* ${GLUE_HOME}/ \
    && rmdir ${GLUE_HOME}/gluetools \
    && rm gluetools.zip

# Debug: List contents of GLUE_HOME
RUN echo "Contents of GLUE_HOME:" && ls -R ${GLUE_HOME}

# Debug: List contents of GLUE_HOME
RUN ls -R ${GLUE_HOME}

# Download GLUE engine jar
RUN mkdir -p ${GLUE_HOME}/lib \
    && wget -O ${GLUE_HOME}/lib/glue-engine.jar http://glue-tools.cvr.gla.ac.uk/downloads/gluetools-core-1.1.113.jar

# Debug: List contents of GLUE_HOME again
RUN echo "Contents of GLUE_HOME after downloading jar:" && ls -R ${GLUE_HOME}

# Fix MySQL user home directory
RUN usermod -d /var/lib/mysql/ mysql

# Set up MySQL for GLUE
RUN service mysql start && \
    mysql -e "CREATE USER 'gluetools'@'localhost' IDENTIFIED BY 'glue12345';" && \
    mysql -e "CREATE DATABASE GLUE_TOOLS CHARACTER SET UTF8;" && \
    mysql -e "GRANT ALL PRIVILEGES ON GLUE_TOOLS.* TO 'gluetools'@'localhost';" && \
    echo "[client]\nuser=gluetools\npassword=glue12345" > /root/.my.cnf && \
    chmod 600 /root/.my.cnf

# Download the NCBI HCV GLUE database
RUN wget https://hcv-glue.cvr.gla.ac.uk/hcv_glue_dbs/ncbi_hcv_glue.sql.gz -O /tmp/ncbi_hcv_glue.sql.gz

# Start MySQL service, import the database, and then stop MySQL
RUN service mysql start && \
    gunzip -c /tmp/ncbi_hcv_glue.sql.gz | mysql GLUE_TOOLS && \
    service mysql stop && \
    rm /tmp/ncbi_hcv_glue.sql.gz

# Install BLAST+
RUN wget ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.2.31/ncbi-blast-2.2.31+-x64-linux.tar.gz -O /tmp/ncbi-blast.tar.gz && \
    tar -xzvf /tmp/ncbi-blast.tar.gz -C /opt && \
    rm /tmp/ncbi-blast.tar.gz && \
    ln -s /opt/ncbi-blast-2.2.31+/bin/* /usr/local/bin/

# Download and install MAFFT
RUN wget https://mafft.cbrc.jp/alignment/software/mafft_7.526-1_amd64.deb -O /tmp/mafft.deb && \
    dpkg -i /tmp/mafft.deb && \
    rm /tmp/mafft.deb

# Download, build and install RAxML
RUN git clone https://github.com/stamatak/standard-RAxML.git /tmp/standard-RAxML && \
    cd /tmp/standard-RAxML && \
    make -f Makefile.SSE3.PTHREADS.gcc && \
    cp raxmlHPC-PTHREADS-SSE3 /usr/local/bin/raxml && \
    cd / && \
    rm -rf /tmp/standard-RAxML

# Debug: List contents of GLUE_HOME again before modification
RUN ls -R ${GLUE_HOME}

RUN config_file="${GLUE_HOME}/conf/gluetools-config.xml" && \
    if [ -f "$config_file" ]; then \
        echo "Found config file at: $config_file" && \
        sed -i '/<database>/,/<\/database>/c\
    <database>\
        <username>gluetools</username>\
        <password>glue12345</password>\
        <vendor>MySQL</vendor>\
        <jdbcUrl>jdbc:mysql://localhost:3306/GLUE_TOOLS?characterEncoding=UTF-8</jdbcUrl>\
    </database>' "$config_file" && \
        sed -i '/<properties>/a\
        <property>\
            <name>gluetools.core.programs.blast.blastn.executable</name>\
            <value>/usr/local/bin/blastn</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.blast.tblastn.executable</name>\
            <value>/usr/local/bin/tblastn</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.blast.makeblastdb.executable</name>\
            <value>/usr/local/bin/makeblastdb</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.blast.temp.dir</name>\
            <value>${GLUE_HOME}/tmp/blastfiles</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.blast.db.dir</name>\
            <value>${GLUE_HOME}/tmp/blastdbs</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.blast.search.threads</name>\
            <value>4</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.mafft.executable</name>\
            <value>/usr/bin/mafft</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.mafft.cpus</name>\
            <value>4</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.mafft.temp.dir</name>\
            <value>${GLUE_HOME}/tmp/mafftfiles</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.raxml.raxmlhpc.executable</name>\
            <value>/usr/local/bin/raxml</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.raxml.raxmlhpc.cpus</name>\
            <value>4</value>\
        </property>\
        <property>\
            <name>gluetools.core.programs.raxml.temp.dir</name>\
            <value>${GLUE_HOME}/tmp/raxmlfiles</value>\
        </property>' "$config_file" && \
        echo "Modified config file successfully"; \
    else \
        echo "Config file not found"; \
    fi

# Create necessary directories for BLAST, MAFFT, and RAxML
RUN mkdir -p ${GLUE_HOME}/tmp/blastfiles \
             ${GLUE_HOME}/tmp/blastdbs \
             ${GLUE_HOME}/tmp/mafftfiles \
             ${GLUE_HOME}/tmp/raxmlfiles

# Debug: Verify the configuration file exists and show its contents
RUN config_file=$(find ${GLUE_HOME} -name gluetools-config.xml) && \
    if [ -f "$config_file" ]; then \
        echo "Config file found at: $config_file" && \
        cat "$config_file"; \
    else \
        echo "Config file not found"; \
    fi

# Set the working directory
WORKDIR ${GLUE_HOME}

RUN echo '#!/bin/bash\n\
echo "Debug: Current working directory:"\n\
pwd\n\
echo "Debug: Listing GLUE_HOME contents"\n\
ls -R ${GLUE_HOME}\n\
echo "Debug: Finding gluetools-config.xml"\n\
config_file="${GLUE_HOME}/conf/gluetools-config.xml"\n\
if [ -f "$config_file" ]; then\n\
    echo "Config file found at: $config_file"\n\
    cat "$config_file"\n\
    # Remove duplicate and incorrect entries\n\
    sed -i "/<\!-- BLAST specific config -->/,/<\!-- RAxML-specific config -->/d" "$config_file"\n\
    sed -i "/<\!-- RAxML-specific config -->/,/<\!-- MAFFT-specific config -->/d" "$config_file"\n\
    sed -i "/<\!-- MAFFT-specific config -->/,/<\!-- SAM\/BAM file processing -->/d" "$config_file"\n\
    echo "Updated config file:"\n\
    cat "$config_file"\n\
else\n\
    echo "Config file not found at $config_file"\n\
    echo "Searching for config file:"\n\
    find /opt -name gluetools-config.xml\n\
fi\n\
echo "Starting MySQL..."\n\
service mysql start\n\
echo "Starting GLUE..."\n\
if [ -f "${GLUE_HOME}/bin/gluetools.sh" ]; then\n\
    ${GLUE_HOME}/bin/gluetools.sh -c "$config_file"\n\
else\n\
    echo "Cannot start GLUE: gluetools.sh not found."\n\
    echo "Contents of ${GLUE_HOME}/bin:"\n\
    ls -l ${GLUE_HOME}/bin\n\
    echo "Searching for gluetools.sh:"\n\
    find /opt -name gluetools.sh\n\
fi' > /startup.sh && chmod +x /startup.sh


# Change the CMD to use this startup script
CMD ["/startup.sh"]

# Start MySQL and run GLUE
#CMD service mysql start 
#&& ${GLUE_HOME}/gluetools/bin/gluetools.sh


