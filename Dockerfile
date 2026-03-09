FROM ghcr.io/kiwix/kiwix-serve:latest@sha256:ca41011170868edfe8e7563b5aabc3b3a9a0870ce0775581d7e30d1993e3bb9d
ENTRYPOINT ["sh", "-c"]
CMD ["exec kiwix-serve /data/*.zim"]
