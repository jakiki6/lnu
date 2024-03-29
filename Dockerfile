FROM debian

WORKDIR /app

RUN apt update && apt install -y gcc g++ wget git make xz-utils bzip2 autoconf automake autotools-dev build-essential bison flex libssl-dev libelf-dev bc

ADD . .

CMD ["./build.sh"]
